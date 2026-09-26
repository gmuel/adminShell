#!/bin/bash

ERR_CLN_CRT=1
ERR_CLN_DST=2

helptxt(){
    cat << EOH
    $0 [options] [DATASET]
    create clones recursively for all child datasets in the form:
    SNAPSHOT-NAME                    CLONE-NAME
    pool/data/set1@my-snapshot       pool/my-snapshot/data/set1

    i.e. calling '$0 pool/data/set1'
    Note, only non-clone datasets will be accepted - i.e. the origin flag must be default.
    On success all but the last clones are destroyed.
    
    Arguments:
        DATASET - non-clone dataset of type filesystem, defaults to root pool (top level dataset of root fs pool)

    Options:
        -h/--help   print this message

    Note - this script relies on lexicographical ordering of snapshots and that all snapshots
    were created recursively with the same name:
    Use case:
        zfs snapshot -r pool/data@my-snapshot01
    ...
        $0 pool/data # new clone created under pool/my-snapshot01
    ...
        zfs snapshot -r pool/data@my-snapshot02
    ...
        $0 pool/data # new clone create under pool/my-snapshot02
                    # previous clone pool/my-snapshot01 destroyed

    Exit status:
        0   creation and destruction succeeded
        $ERR_CLN_CRT    creating clone dataset(s) failed
        $ERR_CLN_DST    destroying clone dataset(s) failed
EOH
}

case "$1" in
    -h|--help)
        helptxt
        exit
        ;;
esac

set -euo pipefail

_zp=${1:-$(mount | awk '{if($3 == "/" && $5 == "zfs"){print $1}}' | cut -d/ -f1 )}
[ -z "$_zp" ] && exit
_clnm0=
. zfs-utils.sh

for _ds in $(zut::listNonCloneDS $_zp ); do
    _lst=$(zut::lastSnap $_ds | tail -1 )
    _snpnm=$(echo $_lst | cut -d@ -f2 )
    [ -z "$_clnm0" ] && _clnm0=$_zp/$_snpnm
    _clnm=$_clnm0${_ds//$_zp/}
    if zut::exists $_clnm ; then
        break
    fi
    zfs clone $_lst $_clnm
done || exit 1

zut::listCloneDS $_zp | grep "^$_zp/[^/]\+\$" | while read _ds; do
    [ -n "$_ds0" ] && zfs destroy -r $_ds0 # && break
    _ds0=$_ds
done || exit 2

