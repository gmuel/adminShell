#!/bin/bash

set -x

[ -z "$1" ] && exit 0
_dr=$(pwd )/$(dirname $0 )
echo $PATH | grep -q $_dr || export PATH=$_dr:$PATH
_ds=rpool/home/$1
who | grep -v $1 && exit 0
_enc=$(zfs get encryption -Ho value $_ds 2>> /dev/null )

if [ -n "$_enc" ] && [ $_enc != "off" ] ; then
	killAll.sh $1 && zfs unmount -u $_ds
fi
