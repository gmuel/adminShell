#!/bin/bash

_mnt=${2:-/mnt}
_ds=
_rt0=
_rt=
_fl=
. zfs-utils.sh
set -x

setMachId(){
    uuidgen | sed "s|\-||g" > $_mnt/etc/machine-id
}
prepChr(){
    for i in /{dev{,/{pts,shm}},proc,run,sys{,firmware/efi/efivars}}; do
        _mpt=$_mnt$i
        if ! mount | grep ; then
            mount --rbind $i $_mpt
        fi
    done
}
mountDS(){
    if [ "$(zfs get mountpoint -Ho value $1 )" != "legacy" ]; then
        zfs set mountpoint=legacy $1
    fi
    if ! mount | grep $1; then
        mount -t zfs $1 $2
        [ -z "$_fl" ] && _fl=on
    fi
}
mountRootUSR(){
    _rt0=$(zut::getRootDS )
    [ -z "$_rt0" ] && return 1
    _rt=$(basename $_rt0 )
    _rt=$(zut::listCloneDS $_zp | grep "$_rt" )
    [ -z "$_rt" ] && return 2
    mountDS $_rt $_mnt
    _ds=$(zut::listCloneDS $_zp | grep "/usr\$" )
    [ -z "$_ds" ] && return 3
    mountDS $_ds $_mnt/usr
}
adjustFS(){
    _fl=$_mnt/etc/fstab
#    cp $_fl{,.1}
    for i in $(grep -v '^#' $_fl | grep zfs | awk '{print $1}'); do
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
    _zp=$(zut::getRootPool )
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
activateBE(){
    prepChr
    chroot $_mnt mount -a
    chroot $_mnt dracut -vfp --regenerate-all
#    zfs set -u mountpoint=/ $_rt
    
}
main(){
    case "$1" in
        -h|--help)
            exit 0
            ;;
        setup|create)
            createBE || initBE || exit $?
            ;;
        activate)
            activateBE
            ;;
    esac
    [ -n "$_fl" ] && umount -R -l $_mnt
}

main $@
