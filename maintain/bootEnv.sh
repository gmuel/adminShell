#!/bin/bash

_mnt=${2:-/mnt}
_ds=
_rt0=
_rt=
_fl=
. zfs-utils.sh
set -x
helptxt(){
    cat << EOH

    $0 [options] OPT-FLAGS [MOUNT-POINT]

    Create, activate or revert bootable environment (BE):
    Relies on blockingClone.sh clones created, adjusts its local fstab and dracut kernel cmdline config
    parameters to allow booting into the clones environment.

    OPT-FLAGS
        create/setup        create a BE, note this will run blockingClone.sh 'POOL-NAME'
        activate            activate BE, create UKI to boot into BE, this will
                            change mountpoints for non-legacy root datasets(!)
        revert/deactivate   change mountpoints where needed

    MOUNT-POINT             mountpoint for processing, defaults to /mnt

    Options:
        -h/--help           print this message
EOH
}

setMachId(){
    uuidgen | sed "s|\-||g" > $_mnt/etc/machine-id
}
prepChr(){
    for i in /{dev{,/{pts,shm}},proc,run,sys{,/firmware/efi/efivars}}; do
        _mpt=$_mnt$i
        if ! mount | grep $_mpt ; then
            mount --rbind $i $_mpt
        fi
    done
    return 0
}
mountDS(){
    if [ "$(zfs get mountpoint -Ho value $1 )" != "legacy" ]; then
        zfs set mountpoint=legacy $1
    fi
    if ! mount | grep $1; then
        mount -t zfs $1 $2
        [ -z "$_fl" ] && _fl=on
    fi
    return 0
}
initDSs(){
    _rt0=$(zut::getRootDS )
    [ -z "$_rt0" ] && return 1
    _zp=$(echo $_rt0 | cut -d/ -f1 )
    _rt=$(basename $_rt0 )
    _rt=$(zut::listCloneDS $_zp | grep "$_rt" )
    [ -z "$_rt" ] && return 2
}
mountRootUSR(){
    initDSs
    mountDS $_rt $_mnt
    _ds=$(zut::listCloneDS $_zp | grep "/usr\$" )
    [ -z "$_ds" ] && return 3
    mountDS $_ds $_mnt/usr
}
adjustFS(){
    _fl=$_mnt/etc/fstab
#    cp $_fl{,.1}
    for i in $(grep -v '^#' $_fl | awk '{if($3 == "zfs"){print $1}}'); do
        sed -i "s|^$i\s|$1${i//$_zp/}\t|g" $_fl # | grep $1
    done
#    systemctl daemon-reload
}
adjustDrct(){
    _cfg=$(for i in $(ls $_mnt/etc/dracut.conf.d/*.conf ); do grep -l "^kernel_cmdline" $i; done )
    [ -z "$_cfg" ] && return 4
    if grep $_rt0 $_cfg ; then
        sed -i "s|$_rt0|$_rt|g" $_cfg # | grep $_rt
    fi
}
adjustMnts(){
    for i in $(zut::listCloneDS $1 ); do
        if grep -q "^[^#\s]\+$(basename $i )\s" /etc/fstab && [ "$(zut::getProp $i mountpoint )" != "legacy" ]; then
            zfs set mountpoint=legacy $i
        fi
    done
}

createBE(){
    mountRootUSR || return $?
    [ "$(cat /etc/machine-id )" != "$(cat $_mnt/etc/machine-id )" ] && return 0
    _bs=$(dirname $_ds )
    adjustFS $_bs
    adjustDrct
    adjustMnts $_zp
    setMachId
}
initBE(){
    blockingClone.sh $_zp || return $?
    createBE
}
filterKver(){
    ls $_mnt/boot | grep vmlinuz- | grep -v 79 | sed "s|vmlinuz\-||g" | tail -1
}
swapMntPt(){
    if [ "$(zfs get mountpoint -Ho value $1 )" != "legacy" ]; then
        zfs set -u mountpoint=/ $2
        zfs set -u mountpoint=legacy $1
    fi

}
resetRtDS(){
    swapMntPt $_rt0 $_rt
}
revert(){
    initDSs
    swapMntPt $_rt $_rt0
    mountDS $_rt $_mnt
    for _efi in $(find /boot/efi/EFI/Linux -type f -name "linux-*-$(cat $_mnt/etc/machine-id ).efi" 2>> /dev/null ); do
        rm -vf $_efi
    done
}
activateBE(){
    mountRootUSR || return $?
    prepChr
    umount /boot/efi
    chroot $_mnt mount -a
    chroot $_mnt dracut -vf --kver $(filterKver )
    resetRtDS
    
}
main(){
    case "$1" in
        -h|--help)
            helptxt
            exit 0
            ;;
        setup|create)
            createBE || initBE || exit $?
            ;;
        activate)
            activateBE
            ;;
        deactivate|revert)
            revert
            ;;
        *)
            echo "unknown operation '$1' - aborting..."
            exit 10
            ;;
    esac
    [ -n "$_fl" ] && umount -R -l $_mnt
}

main $@
