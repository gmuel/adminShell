#!/bin/bash

# listing currently installed kernels
declare -a krnls=( $(apt list --installed 2>> /dev/null \
    | grep ^linux | cut -d' ' -f2 | sort | uniq | grep "^6\(\.[0-9]\+\)\{2\}" \
        | sed "s/\(6\(\.[0-9]\+\)\{2\}\-[0-9]\+\).\+/\1/g" ) )

# create OR pattern
klst=$(echo ${krnls[@]} | sed "s/\s/\\\|/g" )

# run through all efi files and discard all missing in currently installed kernel list
for i in $(ls /boot/efi/EFI/Linux/*.efi ); do
    if ! echo $i | grep "\($klst\)"; then
        mv $i /boot/.dump
    fi
done
