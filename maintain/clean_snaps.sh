#!/bin/bash
set -x
_cnt=${1:-"-2"}
zfs list -rt filesystem rpool -Ho name | while read _ds; do
	_excl="$(zfs list -t snapshot -Ho name $_ds | tail $_cnt )"
	_excl="$(echo $_excl | sed "s=\s\+=\\\|=g" )"
	echo $_excl
	zfs list -t snapshot -Ho name $_ds | grep -v "\($_excl\)" | while read _snp; do
		zfs destroy $_snp
	done
done
