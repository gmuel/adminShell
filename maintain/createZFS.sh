#!/bin/bash

_rtd=
_swp=
_sws=
_zp=
_nswp=
_ecp=
_mnt

_uuid0=
_uuid1=
_rt=
_vb=

helptxt(){
	cat << EOH
	$0 [options] ROOT-DEVICE [SWAP-SIZE] [POOL-NAME] [MOUNT-POINT]
	Prepares a disk or root device for linux distro on ZFS
	Disk layout:
		ROOT-DEVICE GPT
		partition 1 ESP      2G
		partition 2 LUKS/LVM rest-of-disk
		LVM	      1 SWAP     SWAP-SIZE
		LVM       2 ZFS      rest-of-lvm
		
	ZFS dataset layout:
		POOL-NAME              none
		POOL-NAME/ROOT         none
		POOL-NAME/ROOT/lm_cinn /
		POOL-NAME/home         legacy
		POOL-NAME/opt          legacy
		POOL-NAME/usr          legacy
		POOL-NAME/usr/local    legacy
		POOL-NAME/var          legacy
		POOL-NAME/var/cache    legacy
		POOL-NAME/var/lib      legacy
		POOL-NAME/var/log      legacy
		POOL-NAME/var/spool    legacy
		POOL-NAME/var/tmp      legacy
		
	Args:
         ROOT-DEVICE disk/file: e.g. /dev/nvme0n1, /dev/sda, /my_disk_file.img
         SWAP-SIZE   size of swap LV, defaults to memory size (+1G)
         POOL-NAME   ZFS pool name, defaults to rpool
         MOUNT-POINT altroot of ZFS pool
    Options:
    	-h/--help	
EOH
}

getMem(){
    free -h | grep Mem | awk '{print $2}' | sed "s/^\([0-9]\+\)\..\+Gi/\1/g"
}

getUUID(){ blkid -s UUID -o value $1; }

getPartID(){
	parted -s $_rtd print | grep $1 | awk '{print $1}' 
}
gig2Sec(){
    echo $((2*$1*1024*1024))
}

createPart(){
    _efi=${1:-2}
    
    parted -s $_rtd mklabel gpt

    _st=2048s
    _en=$(($(gig2Sec $_efi )+2048))
    parted -s $_rtd mkpart fat32 ${_st}s ${_en}s
    
    if [ -z "$_nswp" ]; then
        _st=$(($_en+2049))
        _en=$(($_st+$(gig2Sec $_sws )+2*16*1024))
        parted -s $_rtd mkpart swap ${_st}s ${_en}s
    fi
    _st=$(($_en+2049))
    parted -s $_rtd mkpart ext4 ${_st}s 100%
}
createLVM(){
    if [ "$_nswp" = "0" ]; then
        pvcreate /dev/mapper/luks-$_uuid0
        vgcreate root_group /dev/mapper/luks-$_uuid0
        lvcreate -L $_sws -n swap root_group
        _sz=$(vgdisplay | grep Free | awk '{print $7}' | sed "s/\([0-9]\+)\..\+/\1/g" )
        _ut=$(vgdisplay | grep Free | awk '{print $8}' | sed "s/\(GiB)/\1/g" )
        _sz=$(($_sz-$_sws))
        if [ -z "$_ut" ] || [ $_sz -le 0 ]; then
        	echo Not enough space on LVM - aborting... 
        	exit 1
        fi
        lvcreate -L ${_sz}G -n root root_group
        _rt=/dev/mapper/root_group-root
        _swp=/dev/mapper/root_group-swap
    else
    	_rt=/dev/mapper/luks-$_uuid0
        _swp=/dev/mapper/luks-$_uuid1
    fi
}
encrypt(){
    _rtd=${1}
    for i in 2 3; do
		_dvc=$_rtd$i
        [ -b $_dvc ] && cryptsetup luksFormat $_dvc && cryptsetup luksOpen $_dvc luks-$(getUUID $_dvc )
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
        -O mountpoint=none -R $_mnt $_zp $_rt

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

setUUIDs(){
	_rid=$(getPartID ext4 )
	if [ "$_rid" = 2 ]; then
		_uuid1=$(getUUID ${_rtd}$(getPartID swap ) )  
	fi
	_uuid0=$(getUUID ${_rtd}$_rid )
}

createFSTAB(){
	mkfs.vfat -F 32 ${_rtd}1
	mkswap $_swp
    printf "# Custom fstab\n# EFI system partition\nUUID=$(getUUID ${_rtd}1 )\t/boot/efi\tvfat\tdefaults,umask=0077\t0\t1\n" > $_mnt/etc/fstab
    printf "# Swap partition\nUUID=$(getUUID $_swp )\tnone\tswap\tdiscard\t0\t0\n" >> $_mnt/etc/fstab
    zfs get mountpoint -rH -o name,value $_zp | grep legacy | while read _ds _mnp; do
    	printf "#$_ds on\n$_ds\t${_ds//$_zp/}\tzfs\trw,relatime,xattr,posixacl,casesensitive\t0\t0\n" >> $_mnt/etc/fstab
    done
    systemctl daemon-reload
}

mountZFS(){
    zfs get mountpoint -rH -o name,value $_zp | grep legacy | while read _ds _mnp; do
    	mount -t zfs $_ds $_mnt${_ds//$_zp/}
    done
}

main(){
	case "$1" in
	-h/--help)
		helpTxt
		exit
	;;
	-n/--no-swap)
		_nswp=0
		shift
		main $@
		exit
	;;
	-e/--encrypt)
		_ecp=0
		shift
		main $@
		exit
	;;
	--verbose)
		_vb=0
		shift
		main $@
		exit
	;;
	esac
	_rtd=$1
	_rtn=$(basename $_rtd )
	if [ "$_rtn" = "nvme0n" ] || [ "$_rtn" = "nvme0n1" ]; then
		[ "$_rtn" = "nvme0n" ] && _rtd="${_rtd}1"
		[ "$_rtn" = "nvme0n1" ] && _rtd="${_rtd}p"
	fi
	_sws=${2:-$(($(getMem )+1))}
	_zp=${3:-rpool}
	_mnt=${4:-/mnt}
	
	createPart 
	[ -n "$_ecp" ] && encrypt
	setUUIDs
	[ "$_nswp" = "0" ] && createLVM
	createPool
	createDSLayout

	#createFSTAB
	mountZFS
}
