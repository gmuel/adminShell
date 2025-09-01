#!/bin/bash


btr(){ btrfs $@; }
btrs(){ btr subvolume $@; }


cd /
declare -a vols=( $(btrs list ./ | cut -d' ' -f9 | grep "^@\(var\|\)\$" ) )

mount -o rw /dev/main_vol/root /mnt


cd /boot
bk=efi.tar
[ -f $bk ] && rm -fv $bk
tar -C /boot/efi --one-file-system -cvf $bk .

cd /mnt

for i in ${vols[@]}; do
    btrs snapshot /mnt/$i "${i}$(date +%Y%m%d )"
done

cd ..
sleep 5

umount /mnt
