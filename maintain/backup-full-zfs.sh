#!/bin/bash


helptxt(){
    cat << EOH
    $0 [options] SRC-DS TRG-DS
    
    Clone all snapshots in source dataset to target dataset incrementally

    Args:
        SRC-DS source dataset
        TRG-DS target dataset

    Options:
        -h/--help   print this message
EOH
}

case $1 in
    -h/--help)
        helptxt
        exit 0
    ;;
esac

_src=$1
_dst=$2
_zp=$(echo $_src | cut -d/ -f1 )
_ropts="-u -o canmount=off -o readonly=on"

zfs get encryption -rHt filesystem -o name,value $_src | while read _ds _enc; do 
    [ "$_enc" = "off" ] && opts=v || opts=vw
    _prt=
    zfs list -Ht snapshot -o name $_ds | while read _snp; do
        _trg=$_dst${_snp//$_zp/}
        if zfs list -H -o name $_trg 2>> /dev/null  | grep -q . ; then
            _prt=$_snp
            continue
        fi
        if [ -n "$_prt" ]; then
            zfs send -$opts -i $_prt $_snp | zfs receive $_ropts $(echo $_trg | cut -d@ -f1 ) || break
        else
            zfs send -$opts $_snp | zfs receive $_ropts $_trg || break
        fi
        _prt=$_snp
    done
done
