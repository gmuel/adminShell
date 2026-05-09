#!/bin/bash

_bck_pl=${1:-backup-pool}
_ds_prnt=$(zfs list -t snapshot $_bck_pl/ROOT -H -o name | tail -1 | sed "s=.\+\(@[0-9\-]\+\)=\1=g" )

zfs list -rt snapshot rpool -H -o name rpool | grep -v rpool\@ | grep 2026-05 | while read _snp; do
	opts=
	if zfs get encryption -H -o value $_snp | grep -q "^aes"; then
		opts="w"
	fi
	ds_nm=$(echo $_snp | sed "s=@[0-9\-]\+==g" )
	trg_sn=$_bck_pl$(echo $_snp | sed "s=rpool==g" )
	if ! zfs list -t snapshot $trg_sn$ 2>> /dev/null; then
		zfs send "-v$opts" -i $ds_nm$_ds_prnt $_snp | zfs receive $_bck_pl$(echo $ds_nm | sed "s=rpool==g" )
	fi
done
