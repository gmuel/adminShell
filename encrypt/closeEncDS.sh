#!/bin/bash

set -x

unmountDS(){
    _ds=$1
    if [ "$(zfs get mountpoint -Ho value $_ds )" = "legacy" ]; then
        umount ${_ds//"$2"/}
        zfs unload-key $_ds
    else
        zfs unmount -u $_ds
    fi
}

[ -z "$1" ] && exit 0
_dr=$(dirname $0 )
[ "${_dr:0:1}" != "/" ] && _dr="$(pwd )/$_dr"
echo $PATH | grep -q $_dr || export PATH=$_dr:$PATH
_zp=$(zpool get name -Ho value | grep "^\([rc]pool\|z\(root\|clone\)\)\$" )
_ds=$_zp/home/$1
mount | grep $_ds || exit 0
who | grep $1 && exit 0
_enc=$(zfs get encryption -Ho value $_ds 2>> /dev/null )

if [ -n "$_enc" ] && [ $_enc != "off" ] ; then
	killAll.sh $1 && unmountDS $_ds $_zp
fi
