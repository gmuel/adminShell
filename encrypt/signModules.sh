#!/bin/bash
set -x
_ds=rpool/boot/efikeys
_cmd=/usr/src/linux-headers-$(uname -r )/scripts/sign-file
_ky='/boot/efikeys/db.'
signMods(){
    for i in $(find /lib/modules -type f -name "$1" ); do
        cd $(dirname $i )
        for j in *; do
            [ "$j" != "${j//'.zst'/}" ] && zstd -d --rm $j
            echo $_cmd sha256 ${_ky}{key,crt} $j
        done
    done
}

mountEDS.sh $_ds

for k in "nvidia.ko*" "vboxdrv.ko"; do
    signMods $k
done
