#!/bin/bash

ERR_SNG_SEND=1
ERR_PRT_SEND=2

helptxt(){
    cat << EOH
    $0 [options] SRC-DS TRG-DS
    
    Clone all snapshots in source dataset to target dataset incrementally

    Args:
        SRC-DS source dataset
        TRG-DS target dataset

    Options:
        -h/--help   print this message
        -l/--last   send only last snapshot per dataset (lexicographically ordered!)
    Exit codes:
        $0 backup completed successfully
        $ERR_SNG_SEND sending of a single/initial snapshot failed
        $ERR_PRT_SEND incremental sending of a snapshot failed
EOH
}
failMsg(){
    if [ -z "$3" ]; then
        echo "Sending '$2' failed with status '$1'"
    else
        echo "Sending '$2' of parent '$3' failed with status '$1'"
    fi
}
sendSnap(){
    _snp=$1
    _trg=$2
    _prt=$3
    local _flg=0
    if [ -n "$_prt" ]; then
        zfs send -$_opts -i $_prt $_snp | zfs receive $_ropts $(echo $_trg | cut -d@ -f1 ) || _flg=$ERR_PRT_SEND
    else
        zfs send -$_opts $_snp | zfs receive $_ropts $_trg || _flg=$ERR_SNG_SEND
    fi
    case $_flg in
        $ERR_SNG_SEND)
            failMsg $ERR_SNG_SEND $_snp
            ;;
        $ERR_PRT_SEND)
            failMsg $ERR_PRT_SEND $_snp $_prt
            ;;
        *)
            ;;
    esac
    return $_flg
}

case $1 in
    -h/--help)
        helptxt
        exit 0
    ;;
    -l|--last)
        _lfl=0
        shift
    ;;
esac

_src=$1
_dst=$2
_zp=$(echo $_src | cut -d/ -f1 )
_opts=
_ropts="-u -o canmount=off -o readonly=on"
set -x
. zfs-utils.sh
_fail=

for _ds in $(zut::listNonCloneDS $_src | grep -v "^$_src\$" ); do # | while read _ds _enc; do  #

    [ "$(zut::getProp $_ds )" = "off" ] && _opts=v || _opts=vw
    _prt=
    if [ -z "$_lfl" ]; then
        for _snp in $(zut::listAllSnaps $_ds ); do
            _trg=$_dst${_snp//$_zp/}
            if ! zut::exists $_trg ; then
                sendSnap $_snp $_trg $_prt || _fail=$?
                [ "$_fail" = "0" ] && _fail= || break
            fi
            _prt=$_snp
        done
    else
        _snps=( $(zut::lastSnap $_ds 2 ) )
        _snp=; _prt=
        if [ -z "${_snps[1]}" ]; then
            _snp=${_snps[0]}
        else
            _snp=${_snps[1]}
            _prt=${_snps[0]}
        fi
        _trg=$_dst${_snp//$_src/}
        if zut::exists $_trg ; then
            continue
        fi
        sendSnap $_snp $_trg $_prt || _fail=$?
    fi
    [ -z "$_fail" ] && [ $_fail -ne 0 ] && exit $_fail
done
