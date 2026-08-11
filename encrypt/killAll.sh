#!/bin/bash

getChildPIDs(){
	ps -ef | grep $1 | awk '{print $2}' | grep -v $1 | sort -r | while read _cid; do
		getChildPIDs $_cid
		echo $_cid
	done
}

ps -u $1 | awk '{print $1}' | sort -r | while read _pid; do
	getChildPIDs $_pid | while read _cid; do
		kill -9 $_cid
	done
	kill -9 $_pid
done
