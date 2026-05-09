#!/bin/sh
set -x
_bck_pl=${1:-backup-pool}
_dt=${2:-$(date +%Y-%m-%d )}
_ds_prnt=$(zfs list -t snapshot $_bck_pl/ROOT -H -o name | tail -1 | sed "s=$_bck_pl/ROOT==g" )
_z_pool=$(uname | grep -q Linux && echo rpool || echo zroot )

zfs list -rt snapshot -H -o name $_z_pool | grep -v $_z_pool\@ | grep $_dt | while read _snp; do
	opts=
	if zfs get encryption -H -o value $_snp | grep -q "^aes"; then
		opts="w"
	fi
	ds_nm=$(echo $_snp | sed "s=@[0-9\-]\{10\}==g" )
	trg_sn=$_bck_pl$(echo $_snp | sed "s=$_z_pool==g" )
	if ! zfs list -t snapshot $trg_sn$ 2>> /dev/null; then
		zfs send "-v$opts" -i $ds_nm$_ds_prnt $_snp | zfs receive $_bck_pl$(echo $ds_nm | sed "s=$_z_pool==g" ) || exit 1
	fi
done
