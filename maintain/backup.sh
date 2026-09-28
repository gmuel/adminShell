#!/bin/bash

_fst=$(mount | awk '{if($3 == "/"){print $5}}' )

_dr=$(cd $(dirname $0); pwd )
if ! echo $PATH | grep -q $_dr; then
	export PATH=$_dr:$PATH
fi

case "$_fst" in
	btrfs)
		backup-btr.sh $@
		;;
	zfs)
		backup-zfs.sh $@
		;;
	*)
		echo Unsupported root filesystem: $_fst
		echo Only supported are btrfs or zfs
		exit 1
		;;
esac
