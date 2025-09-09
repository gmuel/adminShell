#!/bin/bash


btr(){ btrfs $@; }
btrs(){ btr subvolume $@; }

efi=$(blkid -o device -t PARTLABEL=ESP )

mount -o rw /dev/main_vol/root /mnt
cd /mnt

declare -a vols=( $(btrs list ./ | cut -d' ' -f9 | grep "^@\(var\|\)\$" ) )

for i in ${vols[@]}; do
    btrs delete /mnt/$i
done

for i in ${vols[@]}; do
    btrs snapshot /mnt/$i$(date +%Y%m%d ) $i
done


mount -o rw $efi /mnt/\@/boot/efi

rm -vfr /mnt/\@/boot/efi/

tar -C /mnt/\@/boot/efi -xvf /mnt/\@/boot/efi.tar
