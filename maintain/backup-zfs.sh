#!/bin/bash


set -xo pipefail

ERR_NO_DVC=1
ERR_NO_KEY=2
ERR_NO_IMP=3
ERR_NO_MNT=4
ERR_NO_RTP=5
ERR_NO_CFG=6
ERR_NO_SDS=7
ERR_FL_SND=8
ERR_NO_DTS=9

_bck=
_zp=$(zpool get name -Ho value | grep "^\([rc]pool\|z\(root\|clone\)\)\$" )
_fl=bin/zfsDev.map
_dt=$(date +%F )
_sfl=
_blk=not-sent
_snt=last-sent
export PATH=$(pwd )/$(dirname $0 ):$PATH

. zfs-utils.sh

helptxt(){
    cat << EOH
    $0 [OPTIONS] [FLAG]
    
    Create and/or simply incrementally send recursively snapshots from root ZPOOL to a LUKS encrypted backup ZPOOL
    This util requires a LUKS keyfile and a backup config file called zfsDev.map, a four columned file of format:
    
    UUID                    KEYFILE-PATH                            TARGET-DATASET         BACKUP-POOL-NAME
    e.g.
    123456-789a-bcde-f12... /etc/cryptsetup-keys.d/luks-123456-...  dataset/machine-id     backup-disk01234
    
    Above example would contain the complete dataset tree from root ZPOOL:
        backup-disk01234/dataset/machine-id@2020-10-11
        backup-disk01234/dataset/machine-id/dataset01@2020-10-11
        ...
    An initial send will create the direct parent dataset (root pool top level dataset).
    
    The first two columns are required, the last one can be left empty (aka the backup pool is the target dataset)
    All snapshots are named in date format 'YYYY-mm-dd' to ensure proper lexicographical ordering so each pair of snapshots
    per dataset are in a parent snapshot (former) child snapshot (latter) relation.
    
    Arguments
        FLAG   ''/none   create no snapshot
               full      create full system snapshot
               home      create recursive home dataset snapshot
               DS        any valid dataset in root ZPOOL
               
    Options
            -h/--help   print this message
            -l/--last   send only last snapshot per dataset, default is sending all snapshots per dataset
                        requires last snapshots parent to be present in backup ZPOOL
            -d/--date   send only snapshots until DATE string where DATE is a date string in 'YYYY-mm-dd' format
    Exit codes:
        0    no problems encountered
        $ERR_NO_DVC    No backup device found - must be present in config
        $ERR_NO_KEY    No backup keyfile found - must be present in config
        $ERR_NO_IMP    No ZPOOL to import
        $ERR_NO_MNT    Mountpoint /mnt currently in use
        $ERR_NO_RTP    No root pool found - must match rpool or cpool
        $ERR_NO_CFG    No backup config file found
        $ERR_NO_SDS    No such dataset in root/source pool or snapshot (see -d option)
        $ERR_NO_DTS    No date string in format 'YYYY-mm-dd'
        $(($ERR_FL_SND+1))    Single/initial send failed
        $(($ERR_FL_SND+2))    incremental send failed
EOH
}

getDvcSpec(){
    awk "{if(\$1 == \"$1\"){print \$$2}}" $_fl 
}

decrypt(){
    local uuid=$(echo $1 | grep "[a-f0-9\-]\+" )
    if [ -z "$uuid" ] || [ ! -L /dev/disk/by-uuid/$uuid ]; then
        return $ERR_NO_DVC
    fi
    local _ky=$2
    if [ -n "$_ky" ]; then
        if [ ! -L /dev/mapper/luks-$uuid ]; then
            cryptsetup luksOpen /dev/disk/by-uuid/$uuid luks-$uuid --key-file $_ky
        fi
        return 0
    fi
    return $ERR_NO_KEY
}

impPool(){
    local _bck=$1
    if [ -z "$_bck" ]; then
        _lbck=$(zpool import | awk '{if($1 == "pool:"){print $2}}' | grep "backup" | head -1 )
        [ -z "$_bck" ] && return $ERR_NO_IMP
    fi
    zpool list | grep $_bck && return 0
    _mnt=/tmp/$_bck
    if zpool import 2>> /dev/null | grep "$_bck" && ! mount | grep $_mnt; then
        zpool import -f -R $_mnt $_bck
    else
        return $ERR_NO_MNT
    fi
}

createSnap(){
    local _tg=${2:-$_blk}
    if ! zut::exists $1@$_dt ; then
        zut::listNonCloneDS $1 | while read _ds; do
            zfs snapshot $_ds@$_dt
            zfs hold $_tg $_ds@$_dt
        done
    fi
}
reportFail(){
    echo "Backup failed for UUID '$1'"
}
releaseSent(){
    _tg=${2:-$_blk}
    if zut::hasHold $1@$_dt $_tg; then
        zfs release -r $_tg $1@$_dt
    fi
}
lastSent(){
    for _snp in $(zut::listAllSnaps $1 | sort -r ); do
        zut::hasHold $_snp $2 && echo $_snp && return 0
    done
    for _snp in $(zut::listAllSnaps $3 | sort -r ); do
        local _src=$1${_snp//"$3"/}
        if zfs list -Ho name $_src >> /dev/null 2>&1 ; then
            echo $_src && break
        fi
    done
}
clean(){
    zut::exists $_trg${1//"$_zp"/}@$_dt || return $ERR_FL_SND
    zpool export $_bck
    cryptsetup luksClose luks-$_uuid
    releaseSent $1
    return 0
}
copyHolds(){
    for _hld in $(zut::getHold $1 | awk '{print $2}' | grep "^last" | grep -v "$3" ); do
        zfs hold $_hld $2 && zfs release $_hld $1
    done
}
send(){
    local _trg=$4
    local _rop="-u -o canmount=off -o readonly=on"
    for _ds0 in $(zut::listNonCloneDS $1 ); do
        _tds=$_trg${_ds0//$_zp/}
        local _prt=$(lastSent $_ds0 $2 $_tds | cut -d@ -f2 )
        [ "$(zut::getProp $_ds0 encryption )" == "off" ] && _opts=v || _opts=wv
        zut::exists $_tds && zut::exists $_tds@$_dt && continue
        if [ -z "$_prt" ]; then
            zfs send -$_opts $__ds0@$_dt | zfs receive $_rop $_tds@$_dt || return $ERR_FL_SND
        else
            zfs send -$_opts -i $_ds0@{$_prt,$_dt} | zfs receive $_rop $_tds || return $ERR_FL_SND
        fi
        copyHolds $_ds0@{$_prt,$_dt} $2
    done
    clean $1 $2 $1@$_prt
    return $?
}

main(){
    local _src=
    case "$1" in
        -h|--help)
            helptxt
            exit
            ;;
        -l|--last)
            _sfl="-l"
            shift
            main $@
            exit $?
            ;;
        '-d'|'--date')
            
            shift
            _dt0=$1
            echo $_dt0 | grep "^20\(2[6-9]\|[3-9][0-9]\)\-\(0[1-9]\|1[0-1]\)\-\(0[1-9]\|[12][0-9]\|3[01]\)\$" || exit $ERR_NO_DTS
            _src=${2:-$_zp}
            _dt=$_dt0
            zut::exists $_src@$_dt || exit $ERR_NO_SDS
            _snt1=${_snt}_${_src}
            ;;
        full)
            _snt1=${_snt}_$_zp
            _src=$_zp
            createSnap $_zp
            lastHold.sh $_zp
            bootEnv.sh delete
            blockingClone.sh $_zp
            bootEnv.sh create
            ;;
        home)
            _src=$_zp/home
            _snt1=${_snt}_$_src
            createSnap $_src
            lastHold.sh $_src 2
            ;;
        ''|none)
            ;;
        
        *)
            _src=$(zfs list -rHo name $_zp | grep "$1\$" )
            if [ -n "$_ds" ]; then
                _snt1=${_snt}_$_src
                createSnap $_src
                lastHold.sh $_src
            else
                exit $ERR_NO_SDS
            fi
    esac

    [ -z "$_zp" ] && exit $ERR_NO_RTP
    [ ! -f $_fl ] && exit $ERR_NO_CFG
    _snt=
    grep -v "^#" $_fl | while read _uuid _kyfl _ds _bck; do
        decrypt $_uuid $_kyfl || continue
        impPool $_bck || continue
        # _ds=$(getDvcSpec $_uuid 3 )
        if [ -n "$_ds" ]; then
            [ "${ds:0:1}" = "/" ] && _trg=$_bck$_ds || _trg=$_bck/$_ds
        else
            _trg=$_bck
        fi
#        backup-full-zfs.sh $_sfl $_zp $_trg
        send $_src ${_snt1}_$_bck $_trg${_src//"$_zp"/} $_trg $_snt1
        _flg=$?
        if [ $_flg != 0 ]; then
            reportFail $_uuid $_flg
            exit $(($ERR_FL_SND+$_flg+1))
        fi
#        zpool export $_bck
#        cryptsetup luksClose luks-$_uuid
#        [ -z "$_snt" ] && _snt=0
    done
#    [ $? -eq 0 ] && cleanUp $_src $_snt1 $_fl
}

main $@
