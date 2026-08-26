#!/bin/bash
#set -x
getPID(){
	local _cnt=${2:-0}
	[ $_cnt -gt 5 ] && return
	ps -ef | grep -v "\(grep\|^root\)" | grep $1 | awk '{print $2}' | sort -r | grep "[0-9]\+" | while read _pid; do
		[ "$_pid" != "$1" ] && getPID $_pid $(($_cnt+1)) | grep -v "$_pid"
		echo $_pid # $_cnt
	done
}

main(){
	[ -z "$1" ] && echo user id required! && exit 1
	which zpool | grep -q "\S\+" || exit 2
	_zp=$(zpool get name -Ho value )
	_hm=/home/$1
	if ! who | grep -q $1 && [ -d $_hm ] && mount | grep zfs | grep -q $_hm; then
		getPID $1 | while read _pid; do
			echo killing PID: $_pid
			kill -9 $_pid
		done
		_ds=$_zp$_hm
        _ks="$(zfs get keystatus -Ho value $_ds )"
		if [ "$(zfs get mountpoint -Ho value $_ds )" = "legacy" ]; then
		    umount $_hm
		    [[ "$_ks" = "available" ]] && zfs unload-key $_ds
		else
		    [[ "$_ks" = "available" ]] && zfs unmount -u $_ds || zfs unmount $_ds
		fi
	fi
}

main $@
