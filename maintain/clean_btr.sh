#!/bin/bash

_mx=${1:-1}
echo $_mx | grep "^[0-9]\+\$" || exit 1
[ $_mx -lt 1 ] && _mx=1

mount | awk '{if($5 == "btrfs"){print $3}}' | grep -v "/m\(edia\|nt\)" | while read _mpt; do
    declare -a _snps=( $(btrfs sub list -o -s $_mpt | awk '{print $14}' ) )
    _sz=${#_snps[@]}
    for((i=0;i<_sz-_mx;i++)); do
        _snp=$(basename ${_snps[$i]} )
        [ "$_mpt" = "/" ] && btrfs sub delete $_mpt$_snp || btrfs sub delete $_mpt/$_snp
        
    done
done
