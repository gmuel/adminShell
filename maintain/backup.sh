#!/bin/bash

_fst=$(mount | grep "^\S\+\s\+on\s\+/\s" | awk '{print $5}' )
export PATH=$(dirname $0 ):$PATH

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
