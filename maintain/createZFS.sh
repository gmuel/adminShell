#!/bin/bash

_rtd=
_swp=
_sws=
_zp=

_uuid0=
_uuid1=
_rt=

getMem(){
    free -h | grep Mem | awk '{print $2}' | sed "s/^\([0-9]\+\)\..\+Gi/\1/g"
}

getUUID(){ blkid -s UUID -o value $1; }

gig2Sec(){
    echo $((2*$1*1024*1024))
}

createPart(){
    _efi=${1:-2}
    
    parted -s $_rtd mklabel gpt

    _st=2048s
    _en=$(($(gig2Sec $_efi )+2048))
    parted -s $_rtd mkpart fat32 ${_st}s ${_en}s

    if [ "$_nswp" != "0" ]; then
        _st=$(($_en+2049))
        _en=$(($_st+$(gig2Sec $_sws )+2*16*1024))
        parted -s $_rtd mkpart swap ${_st}s ${_en}s
    fi

    _st=$(($_en+2049))
    parted -s $_rtd mkpart ext4 ${_st}s 100% 
}
createLVM(){
    if [ "$_nswp" = "0" ]; then
        pvcreate /dev/mapper/luks-$uuid0
        vgcreate root_group /dev/mapper/luks-$uuid0
        lvcreate -L $_sws -n swap root_group
        
        lvcreate -L 
    fi
}
encrypt(){
    _rtd=${1}
    for i in ${_rtd}{2,3}; do
        [ -b $i ] && cryptsetup luksFormat $i && cryptsetup luksOpen $i luks-$(getUUID $i )
    done
}

createPool(){
    if ! dpkg --list *zfs*  | grep ^ii; then
        apt update
        apt install -y zfsutils-linux
    fi
    
    zpool create -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
        -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
        -O compression=zstd -O normalization=formD -O relatime=on \
        -O mountpoint=none -R /mnt $_zp $_rt

}
createDSLayout(){
    zfs create -o mountpoint=none $_zp/ROOT
    zfs create -o mountpoint=/ $_zp/ROOT/lin_mint
    for i in /{home,opt,usr{,/local},var{,/{cache,lib,log,spool,tmp}}}; do
        opts="-o mountpoint=legacy"
        [ "$i" = "/var/tmp" ] && opts="-o compression=off $opts"
        zfs create $opts $_zp$i
    done
    zpool set -o bootfs=$_zp/ROOT/lin_mint $_zp
}



createFSTAB(){
    
}
