#!/bin/bash
dr=$(dirname $0 )
eval "$(grep declare $dr/Step4.sh )"

for i in $(for j in ${drs[@]}; do echo $j; done | sort -r ); do
    umount -l /mnt$i
done
