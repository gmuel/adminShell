#!/bin/bash
set -x

[ -z "$1" ] && exit

_zp=$(zpool get name -Ho value )
_dr=$1
sz=${#_dr}
[ "${_dr:$(($sz-1)):1}" != "/" ] && _dr="$_dr/"
_own=$(basename $_dr )
_own=${_own//'/'/}

for i in cache local mozilla var; do
    _src=$_dr.$i
    mount | grep $_src | grep zfs && continue
    mv $_dr.{$i,tmp_$i}
    mkdir $_src
    zfs create -o compression=off -o mountpoint=$_src $_zp$_src
    if ! mount | grep $_src; then
        zfs mount $_zp$_src
    fi
    chown $_own:$_own $_src
    mv -v $_dr.tmp_$i/* $_src
    mv -v $_dr.tmp_$i/.* $_src
    rmdir $_dr.tmp_$i
done

