#!/bin/bash

_mnt=${2:-/mnt}
_ds=
_rt0=
_rt=
_fl=
_zp=
NO_RT_DVC=1
NO_NW_RT=2
NO_USR_DS=3
NO_DRC_CFG=4
NO_MCH_ID=5
NO_OP_STR=6

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
        delete/remove       remove BE

    MOUNT-POINT             mountpoint for processing, defaults to /mnt

    Options:
        -h/--help           print this message
    
    Exit codes:
    	0	operation completed successfully
    	$NO_RT_DVC	no ZFS root dataset found
    	$NO_NW_RT	no root clone found
    	$NO_USR_DS	no /usr dataset found
    	$NO_DRC_CFG	no dracut config file found
    	$NO_MCH_ID	machine id matched while activation (should be different)
    	$NO_OP_STR	unknown or unsupported operation flag
EOH
}

setMachId(){
    uuidgen | sed "s|\-||g" > $_mnt/etc/machine-id
}
baseSys(){
    for i in /{dev{,/{pts,shm}},proc,run,sys{,/firmware/efi/efivars}}; do
        echo $i
    done
}
prepChr(){
    for i in $(baseSys ); do
        _mpt=$_mnt$i
        if ! mount | grep -q $_mpt ; then
            mount --bind $i $_mpt
        fi
    done
    return 0
}
postChr(){
    for i in $(baseSys | sort -r ); do
        _mpt=$_mnt$i
        if mount | grep -q $_mpt ; then
            umount -l $_mpt
        fi
    done
    return 0
}
mountDS(){
    if ! mount | grep $1; then
        _ori=$(zut::getProp $1 origin | cut -d@ -f1 )
        [ -z "$_ori" ] && return 0
        _mpt=$(zfs get mountpoint -Ho value $_ori )
        case "$_mpt" in
            legacy)
                zfs set -u mountpoint=$_mpt $1
                mount -t zfs $1 $2
                ;;
            none)
                return 0
                ;;
            *)
                [ "$_mpt" = "/" ] && zfs set -u mountpoint=/mnt $1 || zfs set -u mountpoint=/mnt$_mnt $1
                zfs set -u canmount=noauto $1
                zfs mount $1
                ;;
        esac
        [ -z "$_fl" ] && _fl=on
    fi
    return 0
}
initDSs(){
    _rt0=$(zut::getRootDS )
    [ -z "$_rt0" ] && return $NO_RT_DVC
    _zp=$(echo $_rt0 | cut -d/ -f1 )
    _rt=$(basename $_rt0 )
    _rt=$(zut::listCloneDS $_zp | grep "$_rt" )
    [ -z "$_rt" ] && return $NO_NW_RT
    return 0
}
mountRootUSR(){
    initDSs || return $?
    mountDS $_rt $_mnt
    _ds=$(zut::listCloneDS $_zp | grep "/usr\$" )
    [ -z "$_ds" ] && return $NO_USR_DS
    mountDS $_ds $_mnt/usr
}
adjustFS(){
    _fl=$_mnt/etc/fstab
#    cp $_fl{,.1}
    for i in $(grep -v '^#' $_fl | awk '{if($3 == "zfs"){print $1}}' | grep "rpool/\(ROOT/[^/]\+\|usr\|var\)\$"); do
        sed -i "s|^$i\s|$1${i//$_zp/}\t|g" $_fl # | grep $1
    done
#    systemctl daemon-reload
}
adjustDrct(){
    _cfg=$(for i in $(ls $_mnt/etc/dracut.conf.d/*.conf ); do grep -l "^kernel_cmdline" $i; done )
    [ -z "$_cfg" ] && return $NO_DRC_CFG
    if grep $_rt0 $_cfg ; then
        sed -i "s|$_rt0|$_rt|g" $_cfg # | grep $_rt
    fi
}
adjustMnts(){
    for i in $(zut::listCloneDS $1 | grep "rpool\(/[^/]\+\)/\(ROOT/[^/]\+\|usr\|var\)\$" ); do
        _ds=$(zut::getProp $i origin | cut -d@ -f1 )
        if [ -n "$_ds" ]; then
            _mpt=$(zfs get mountpoint -Ho value $_ds )
            [ "$_mpt" = "/" ] && zfs set -u mountpoint=/mnt $i || zfs set -u mountpoint=$_mpt $i
            zfs set -u canmount=$(zfs get canmount -Ho value $_ds ) $i
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
    _kver=$(uname -r )
    if [ -n "$_kver" ] && ls $_mnt/boot | grep -q "vmlinuz-$_kver"; then
        echo $_kver
    else
        ls $_mnt/boot | grep "vmlinuz-" | grep -v 79 | sed "s|vmlinuz\-||g" | tail -1
    fi
}
swapMntPt(){
    if [ "$(zfs get mountpoint -Ho value $1 )" != "legacy" ]; then
        echo zfs set -u mountpoint=/ $2
        # echo zfs set -u mountpoint=legacy $1
    fi

}
resetRtDS(){
    swapMntPt $_rt0 $_rt
}
revert(){
    initDSs
    mountDS $_rt $_mnt
    local _dr=/boot/efi/EFI/Linux
    _beid=$(cat $_mnt/etc/machine-id )
    [ "$(cat /etc/machine-id )" = "$_beid" -o ! -d $_dr ] && return 0
    for _efi in $(find $_dr -type f -name "linux-*-$_beid.efi" 2>> /dev/null ); do
        rm -vf $_efi
    done
}
activateBE(){
    mountRootUSR || return $?
    prepChr
    if [ "$(cat /etc/machine-id )" != "$(cat $_mnt/etc/machine-id )" ]; then
		umount /boot/efi
		systemctl daemon-reload
		chroot $_mnt mount -a
		chroot $_mnt dracut -vf --kver $(filterKver )
		resetRtDS
		return 0
    fi
    return $NO_MCH_ID
}
destroyParents(){
    [ -z "$2" ] && return 0
    if [ "$1" != "$2" ]; then
        [ "$(dirname $2 )" = "$1" ] && zfs destroy -r $2 && return 0
        destroyParents $1 $(dirname $2 )
    fi
}
main(){
    case "$1" in
        -h|--help)
            helptxt
            return 0
            ;;
        setup|create)
            createBE || initBE || return $?
            ;;
        activate)
            activateBE || return $?
            ;;
        deactivate|revert)
            revert
            ;;
        delete|remove)
            revert
            _cl=$(zut::listCloneDS $_zp | head -1 )
            [ -n "$_fl" ] && postChr && umount -R $_mnt && mount -a
            destroyParents $_zp $_cl
            _fl=
            ;;
        *)
            echo "unknown operation '$1' - aborting..."
            return $NO_OP_STR
            ;;
    esac
    if [ -n "$_fl" ]; then
        postChr && umount -R $_mnt && mount -a || return $?
    fi
    return 0
}

main $@
