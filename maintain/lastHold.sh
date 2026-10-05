#!/bin/bash

ERR_CLN_CRT=1
ERR_CLN_DST=2
_FLG=full_sys

helptxt(){
    cat << EOH
    $0 [options] [DATASET] [NO-OF-TAGGED]
    create holds recursively for the last snapshot of all children datasets in the form:
    SNAPSHOT-NAME                    TAG
    pool/data/set1@my-snapshot       'set1'

    i.e. calling '$0 pool/data/set1'. Note, only non-clone datasets 
    will be accepted - i.e. the origin flag must be default.
    On success all but the last holds are destroyed.
    
    Arguments:
        DATASET - non-clone dataset of type filesystem, defaults to root pool (top level dataset of root fs pool)
        NO-OF-TAGGED - maximal number of tagged snapshots to keep, defaults to 1
    Options:
        -h/--help   print this message

    A full ZFS pool hold will have the tag '$_FLG', while any other dataset will have the base name of its dataset:
        EXAMPLE              LAST-SNAPSHOT                          TAG
        $0 pool/data/set1 -> pool/data/set1@999-last-snapshot   -> 'set1'
        $0 pool/data      -> pool/data@999-last-snapshot        -> 'data'
        $0 pool           -> pool@999-last-snapshot             -> '$_FLG'

    Note - this script relies on lexicographical ordering of snapshots and that all snapshots
    were created recursively with the same name:
    Use case:
        zfs snapshot -r pool/data@my-snapshot01
    ...
        $0 pool/data # new hold created with name 'data'
    ...
        zfs snapshot -r pool/data@my-snapshot02
    ...
        $0 pool/data # new hold create under pool/my-snapshot02
                    # previous hold on pool/my-snapshot01 released

    Exit status:
        0   creation and destruction succeeded
        $ERR_CLN_CRT    creating hold failed
        $ERR_CLN_DST    releasing hold failed
EOH
}

case "$1" in
    -h|--help)
        helptxt
        exit
        ;;
esac

set -xo pipefail

. zfs-utils.sh
_zp=${1:-$(zut::getRootPool )}
[ -z "$_zp" ] && exit
_sz=${2:-1}
[ $_sz -gt 3 ] && _sz=3
_zp0=$(echo $_zp | cut -d/ -f2 )
[ "$_zp0" = "$_zp" ] && _flg=$_FLG || _flg=$(basename $_zp )
_clnm0=
_snpnm=
_lsts=( $(zut::lastSnap $_zp $_sz ) )
_snpnm=$(_str=; for i in ${_lsts[@]}; do _tmp=$(echo $i | cut -d@ -f2 ); [ -z "$_str" ] && _str=$_tmp || _str="$_str\|$_tmp"; done; echo $_str )

for _lst in ${_lsts[@]}; do
    if ! zut::hasHold $_lst $_flg ; then
        zfs hold -r $_flg $_lst # $_clnm
    fi
done || exit 1

for _snp in $(zut::listAllSnaps $_zp | grep -v "\($_snpnm\)" ); do
    if zut::hasHold $_snp $_flg ; then
        zfs release -r $_flg $_snp # $_clnm
    fi
done || exit 2

