#!/bin/bash


set -x

ERR_NO_DVC=1
ERR_NO_KEY=2
ERR_NO_IMP=3
ERR_NO_MNT=4
ERR_NO_RTP=5
ERR_NO_CFG=6

_bck=
_zp=$(zpool get name -Ho value | grep "^\(r\|c\)pool\$" )
[ -z "$_zp" ] && exit $ERR_NO_RTP
_fl=bin/zfsDev.map
[ ! -f $_fl ] && exit $ERR_NO_CFG
_dt=$(date +%Y-%m-%d )

helptxt(){
    cat << EOH
    $0 [OPTIONS] [FLAG]
    
    Create and/or simply incrementally send all snapshots from root ZPOOL to a LUKS encrypted backup ZPOOL
    This util requires a LUKS keyfile and a backup config file called zfsDev.map, a three columned file of format:
    
    UUID                    KEYFILE-PATH                            TARGET-DATASET
    e.g.
    123456-789a-bcde-f12... /etc/cryptsetup-keys.d/luks-123456-...  dataset/machine-id
    
    The first two columns are required, the last one can be left empty (aka the backup pool is the target dataset)
    
    Arguments
        FLAG   ''/none   empty string means no snapshot created
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
               
EOH
}

getDvcSpec(){
    grep $1 $_fl | awk "{print \$$2}" 
}

decrypt(){
    local uuid=$(echo $1 | grep "[a-f0-9\-]\+" )
    if [ -z "$uuid" ] || [ ! -L /dev/disk/by-uuid/$uuid ]; then
        exit $ERR_NO_DVC
    fi
    ky=$(getDvcSpec $uuid 2 )
    if [ -n "$ky" ]; then
        if [ ! -L /dev/mapper/luks-$uuid ]; then
            cryptsetup luksOpen /dev/disk/by-uuid/$uuid luks-$uuid --key-file $ky
        fi
    else
        exit $ERR_NO_KEY
    fi
}

impPool(){
    _bck=$(zpool import | grep "pool:" | awk '{print $2}' )
    [ -z "$_bck" ] && exit $ERR_NO_IMP
    if ! mount | grep /mnt; then
        zpool import -f -R /mnt $_bck
    else
        exit $ERR_NO_MNT
    fi
}

createSnap(){
    if ! zfs list -Ht snapshot -o name $1 | grep $_dt ; then
        zfs snapshot -r $1@$_dt
    fi
}

main(){
    case "$1" in
        -h|--help)
            helptxt
            exit
            ;;
        full)
            createSnap $_zp
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
            fi
    esac
    for uuid in $(awk '{print $1}' $_fl ); do
        decrypt $uuid || continue
        impPool || continue
        _ds=$(getDvcSpec $uuid 3 )
        if [ -n "$_ds" ]; then
            [ "${ds:0:1}" = "/" ] && _trg=$_bck$_ds || _trg=$_bck/$_ds
        else
            _trg=$_bck
        fi
        backup-full-zfs.sh $_zp $_trg
        zpool export $_bck
        cryptsetup luksClose luks-$uuid
    done
}

main $@
