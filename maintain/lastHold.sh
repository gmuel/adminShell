#!/bin/bash

ERR_CLN_CRT=1
ERR_CLN_DST=2
_FLG=full_sys

helptxt(){
    cat << EOH
    $0 [options] [DATASET]
    create holds recursively for the last snapshot of all child datasets in the form:
    SNAPSHOT-NAME                    TAG
    pool/data/set1@my-snapshot       '$_FLG'

    i.e. calling '$0 pool/data/set1'. Note, only non-clone datasets 
    will be accepted - i.e. the origin flag must be default.
    On success all but the last holds are destroyed.
    
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

set -xo pipefail

_zp=${1:-$(mount | awk '{if($3 == "/" && $5 == "zfs"){print $1}}' | cut -d/ -f1 )}
[ -z "$_zp" ] && exit
_clnm0=
. zfs-utils.sh
_snpnm=

for _ds in $(zut::listNonCloneDS $_zp ); do
    _lst=$(zut::lastSnap $_ds )
    [ -z "$_snpnm" ] && _snpnm=$(echo $_lst | cut -d@ -f2 )
    if ! zfs holds $_lst -Ho tag 2>> /dev/null | grep $_snpnm ; then
    	echo zfs hold $_FLG $_lst # $_clnm
	fi
done || exit 1

for _ds in $(zut::listNonCloneDS $_zp ); do
    for _snp in $(zut::listAllSnaps $_ds | grep -v $snpnm ); do
    	echo zfs release $_FLG $_snp
    done
done || exit 2

