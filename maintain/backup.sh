#!/bin/bash

_fst=$(mount | grep "\s/\s" | awk '{print $5}' )

case "$_fst" in
	zfs)
		backup-zfs.sh $@
		;;
	btrfs)
		backup-btr.sh $@
		;;
esac
