#!/bin/bash


set -x

ERR_NO_DVC=1
ERR_NO_KEY=2
ERR_NO_IMP=3
ERR_NO_MNT=4
ERR_NO_RTP=5
ERR_NO_CFG=6
ERR_NO_SDS=7

_bck=
_zp=$(zpool get name -Ho value | grep "^\([rc]pool\|z\(root\|clone\)\)\$" )
_fl=bin/zfsDev.map
_dt=$(date +%Y-%m-%d )
_sfl=
export PATH=$(pwd )/$(dirname $0 ):$PATH
. zfs-utils.sh

helptxt(){
    cat << EOH
    $0 [OPTIONS] [FLAG]
    
    Create and/or simply incrementally send all snapshots from root ZPOOL to a LUKS encrypted backup ZPOOL
    This util requires a LUKS keyfile and a backup config file called zfsDev.map, a four columned file of format:
    
    UUID                    KEYFILE-PATH                            TARGET-DATASET         BACKUP-POOL-NAME
    e.g.
    123456-789a-bcde-f12... /etc/cryptsetup-keys.d/luks-123456-...  dataset/machine-id     backup-disk01234
    
    The first two columns are required, the last one can be left empty (aka the backup pool is the target dataset)
    
    Arguments
        FLAG   ''/none   create no snapshot
               full      create full system snapshot
               home      create recursive home dataset snapshot
               DS        any valid dataset in root ZPOOL
               
    Options
            -h/--help   print this message
            
    Exit codes:
        0    no problems encountered
        $ERR_NO_DVC    No backup device found - must be present in config
        $ERR_NO_KEY    No backup keyfile found - must be present in config
        $ERR_NO_IMP    No ZPOOL to import
        $ERR_NO_MNT    Mountpoint /mnt currently in use
        $ERR_NO_RTP    No root pool found - must match rpool or cpool
        $ERR_NO_CFG    No backup config file found
        $ERR_NO_SDS    No such dataset in root/source pool
        $(($ERR_NO_SDS+1))    Single/initial send failed
        $(($ERR_NO_SDS+2))    incremental send failed
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
    [ -z "$_bck" ] && exit $ERR_NO_IMP
    zpool list | grep $_bck && return 0
    if zpool import 2>> /dev/null | grep "$_bck" && ! mount | grep /mnt; then
        zpool import -f -R /mnt $_bck
    else
        return $ERR_NO_MNT
    fi
}

createSnap(){
    if ! zut::exists $1@$_dt ; then
        zut::listNonCloneDS $1 | while read _ds; do
            echo zfs snapshot $_ds@$_dt
        done
    fi
}
reportFail(){
    echo "Backup failed for UUID '$1'"
}

main(){
    case "$1" in
        -h|--help)
            helptxt
            exit
            ;;
        -c|--complete)
            _sfl="-l"
            shift
            main $@
            exit $?
        ;;
        full)
            createSnap $_zp
            blockingClone.sh $_zp
            ;;
        home)
            createSnap $_zp/home
            ;;
        ''|none)
            ;;
        *)
            _ds=$(zfs list -rHo name $_zp | grep $1 )
            if [ -n "$_ds" ]; then
                createSnap $_ds
            else
                exit $ERR_NO_SDS
            fi
    esac

    [ -z "$_zp" ] && exit $ERR_NO_RTP
    [ ! -f $_fl ] && exit $ERR_NO_CFG

    grep -v "^#" $_fl | while read _uuid _kyfl _ds _bck; do
        decrypt $_uuid $_kyfl || continue
        impPool $_bck || continue
        # _ds=$(getDvcSpec $_uuid 3 )
        if [ -n "$_ds" ]; then
            [ "${ds:0:1}" = "/" ] && _trg=$_bck$_ds || _trg=$_bck/$_ds
        else
            _trg=$_bck
        fi
        backup-full-zfs.sh $_sfl $_zp $_trg
        _flg=$?
        if [ $_flg != 0 ]; then
            reportFail $_uuid $_flg
            exit $(($ERR_NO_SDS+$_flg+1))
        fi
        zpool export $_bck
        cryptsetup luksClose luks-$_uuid
    done
}

main $@
