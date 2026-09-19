#!/bin/bash

ERR_SNG_SEND=1
ERR_PRT_SEND=2

_src=$1
_dst=$2
_zp=$(echo $_src | cut -d/ -f1 )
_opts=
_ropts="-u -o canmount=off -o readonly=on"

helptxt(){
    cat << EOH
    $0 [options] SRC-DS TRG-DS
    
    Clone all snapshots in source dataset to target dataset incrementally

    Args:
        SRC-DS source dataset
        TRG-DS target dataset

    Options:
        -h/--help   print this message
    Exit codes:
        $0 backup completed successfully
        $ERR_SNG_SEND sending of a single/initial snapshot failed
        $ERR_PRT_SEND incremental sending of a snapshot failed
EOH
}
failMsg(){
    [ -z "$4" ] && echo "Sending '$2' failed with status '$3'" && exit $1 \
        || echo "Sending '$2' of parent '$4' failed with status '$3'" && exit $1
}
sendSnap(){
    _snp=$1
    _trg=$2
    _prt=$3
    if [ -n "$_prt" ]; then
        zfs send -$_opts -i $_prt $_snp | zfs receive $_ropts $(echo $_trg | cut -d@ -f1 ) || exit failMsg $ERR_PRT_SEND $_snp $? $_prt
    else
        zfs send -$_opts $_snp | zfs receive $_ropts $_trg || failMsg $ERR_SNG_SEND $_snp $?
    fi
}

case $1 in
    -h/--help)
        helptxt
        exit 0
    ;;
esac



zfs get encryption -rHt filesystem -o name,value $_src | while read _ds _enc; do 
    [ "$_enc" = "off" ] && _opts=v || _opts=vw
    _prt=
    zfs list -Ht snapshot -o name $_ds | while read _snp; do
        _trg=$_dst${_snp//$_zp/}
        if ! zfs list -H -o name $_trg 2>> /dev/null  | grep -q . ; then
            sendSnap $_snp $_trg $_prt
        fi
        _prt=$_snp
    done
done
