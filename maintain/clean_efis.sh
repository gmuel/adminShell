#!/bin/bash

# listing currently installed kernel version ids
declare -a krnls=( $(ls /boot/vmlinuz-* \
        | sed "s/.\+\([5-7]\(\.[0-9]\+\)\{2\}\-[0-9]\+\).\+/\1/g" ) )

# create OR pattern
klst=$(echo ${krnls[@]} | sed "s/\s/\\\|/g" )

# run through all efi files and discard all missing in currently installed kernel list
for i in $(ls /boot/efi/EFI/Linux/*.efi ); do
    if ! echo $i | grep -q "\($klst\)"; then
        mv $i /boot/.dump
    fi
done
