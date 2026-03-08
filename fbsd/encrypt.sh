#!/bin/sh

createKey(){
    dr=$(dirname $ky_fl )
    [ ! -d $dr ] && mkdir -p $dr
    dd if=/dev/random of=$ky_fl bs=64 count=1
}

createGELI(){
#    geli init -g -K $ky_fl -s 4096 /dev/$dvc
    geli init -g -s 4096 /dev/$dvc
}

dvc=$1
if [ -z "$dvc" ] || [ ! -c /dev/$dvc ] ; then
    echo no such device $dvc - aborting
    return 1    
fi
ky_fl=${2:-/root/.key/${dvc}.key}
createKey
createGELI
