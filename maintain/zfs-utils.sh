#!/usr/bin/env bash

[ -z "$_ZFS_UTILS_SH" ] && _ZFS_UTILS_SH=on || return 0

# set -Eeuo pipefail
# shopt -s inherit_errexit 2>/dev/null || true

zut::listAllDSs(){
    zfs get ${2:-encryption} -${4:-""}Ht ${3:-filesystem} -o name,value $1
}
zut::listByType(){
    zut::listAllDSs $1 origin $2 $3
}
zut::getProp(){
    zut::listAllDSs $1 $2 $3 | awk '{print $2}'
}
zut::listAllDSnCl(){
    zut::listByType $1 filesystem r
}
zut::listNonCloneDS(){
    zut::listAllDSnCl $1 | awk '{if($2 == "-"){print $1}}'
}
zut::listCloneDS(){
    zut::listAllDSnCl $1 | awk '{if($2 != "-"){print $1}}'
}
zut::listAllSnaps(){
    zut::listByType $1 snapshot | awk '{print $1}'
}
zut::firstSnap(){
    zut::listAllSnaps $1 | head -${2:-1}
}
zut::lastSnap(){
    zut::listAllSnaps $1 | tail -${2:-1}
}
zut::exists(){
    [ -n "$1" ] && zfs list -Ho name $1 2>/dev/null | grep -q "$1" || return 1
}
zut::hasHold(){
    _tg=${2:-$1}
    if [ "$_tg" = "$1" ]; then
        zfs holds $1 -H 2>> /dev/null | grep "${2:-$1}"
    else
        zfs holds $1 -H 2>> /dev/null | awk "{if(\$2 == \"$_tg\"){print \$0}}" | grep "$1"
    fi
}
zut::listNoHoldSnaps(){
    for _snp in $(zut::listAllSnaps $1 ); do
        if ! zut::hasHold $_snp ; then
            echo $_snp
        fi
    done
}
zut::getRootPool(){
    mount | awk '{if($3 == "/" && $5 == "zfs"){print $1}}' | cut -d/ -f1
}

