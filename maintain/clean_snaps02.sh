#!/bin/bash

set -x
_cnt=${1:-"2"}
declare -a _snps=( )
[ $_cnt -lt 1 ] && _cnt=2

zfs list -rt filesystem rpool -Ho name | while read _ds; do
    _snps=( $(zfs list -t snapshot -Ho name $_ds ) )
    _sz=${#_snps[@]}
    if [ $_sz -gt $_cnt ]; then
        _sz=$(($_sz-$_cnt))
        for ((i=0;i<$_sz;i++)); do
            echo zfs destroy ${_snps[$i]}
        done
    fi
done
