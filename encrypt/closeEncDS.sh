#!/bin/bash

set -x

[ -z "$1" ] && exit 0
_dr=$(dirname $0 )
[ "${_ds:0:1}" != "/" ] && _dr="$(pwd )/$_dr"
echo $PATH | grep -q $_dr || export PATH=$_dr:$PATH
_ds=rpool/home/$1
mount | grep $_ds || exit 0
who | grep $1 && exit 0
_enc=$(zfs get encryption -Ho value $_ds 2>> /dev/null )

if [ -n "$_enc" ] && [ $_enc != "off" ] ; then
	killAll.sh $1 && zfs unmount -u $_ds
fi
