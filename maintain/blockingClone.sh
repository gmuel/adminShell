#!/bin/bash

helptxt(){
    cat << EOH
    $0 [options] [DATASET]
    create clones recursively for all child datasets in the form:
    SNAPSHOT-NAME                    CLONE-NAME
    pool/data/set1@my-snapshot       pool/data/set1/my-snapshot/data/set1

    i.e. calling '$0 pool/data/set1'
    Note, only non-clone datasets will be accepted - i.e. the origin flag must be default.
    On success all but the last clones are destroyed
EOH
}

case "$1" in
    -h|--help)
        helptxt
        exit
        ;;
esac

set -x
_zp=${1:-$(mount | awk '{if($3 == "/" && $5 == "zfs"){print $1}}' | cut -d/ -f1 )}
[ -z "$_zp" ] && exit
_clnm0=
. zfs-utils.sh

for _ds in $(listNonCloneDS $_zp ); do
    _lst=$(zfs list -Ht snapshot -o name $_ds | tail -1 )
    _snpnm=$(echo $_lst | cut -d@ -f2 )
    [ -z "$_clnm0" ] && _clnm0=$_zp/$_snpnm
    _clnm=$_clnm0${_ds//$_zp/}
    if zfs list -Ho name $_clnm 2>> /dev/null | grep -q .; then
        break
    fi
    zfs clone $_lst $_clnm
done || exit 1

listCloneDS $_zp | grep "^$_zp/[^/]\+\$" | while read _ds; do
    [ -n "$_ds0" ] && zfs destroy -r $_ds0 # && break
    _ds0=$_ds
done || exit 2

