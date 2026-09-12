#!/bin/bash
set -x
getChildPIDs(){
    _dpt=${2:-0}
    [ -n "$1" ] && ps -ef | grep $1 | awk '{print $2}' | grep -v $1 | sort -r | grep "[0-9]\+" | while read _cid; do
		[ $_dpt -le 3 ] && getChildPIDs $_cid $(($_dpt+1))
		echo $_cid
	done
}

if [ -z "$1" ] || [ ! -d /home/$1 ] || ! mount | grep $1; then
	exit 1
fi

ps -u $1 | awk '{print $1}' | sort -r | while read _pid; do
	getChildPIDs $_pid | while read _cid; do
		kill -9 $_cid
	done
	kill -9 $_pid
done
