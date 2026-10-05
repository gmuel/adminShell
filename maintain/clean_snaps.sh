#!/bin/bash
# set -x
. zfs-utils.sh
_zp=${1:-$(zut::getRootPool )}

for _snp in $(zut::listNoHoldSnaps $_zp ); do
    zfs destroy -rv $_snp
done
