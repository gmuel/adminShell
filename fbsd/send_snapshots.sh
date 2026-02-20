#!/bin/sh
sn_vol=${1:-$(date +%Y%m%d )}
bck_pth=backup-samt4/data
for i in $(zfs list -t snapshot | grep zroot | awk '{print $1}' ); do
    trg="$(echo $i | sed 's/zroot\/\{0,1\}//g' | sed "s/@$sn_vol//g" )"
    [ -n "$trg" ] && trg="/$trg"
    if ! zfs list -t snapshot | grep $bck_pth$trg | grep $sn_vol; then
        zfs send -v $i | zfs receive $bck_pth$trg || break
    fi
done

