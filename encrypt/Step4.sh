#!/bin/bash

[ -z "$1" ] && echo Disk device missing - aborting && exit 1
rtd=$1
efi=${rtd}
dvc=${rtd}

if echo $rtd | grep nvme ; then
    efi=${efi}p
    dvc=${dvc}p
fi
efi=${efi}1
dvc=${dvc}2

uuid=$(blkid -s UUID -o value $dvc )
lxid=luks-$uuid
dmd=/dev/mapper/$lxid

[ ! -L $dmd ] && cryptsetup luksOpen $dvc $lxid
lmd=/dev/mapper/main_vol-root
lmdm=$(mount | grep $lmd )
dmdm=$(mount | grep $dmd )
sleep 20s
if [ -L $lmd ] && [ -z "$lmdm" ]; then
    vgchange -a y main_vol
    mount -o rw,subvol=@ $lmd /mnt
elif [ -L $dmd ] && [ -z "$dmdm" ] && [ -z "$lmdm" ]; then
    mount -o rw,subvol=@ $dmd /mnt
fi

systemctl daemon-reload
[ ! -d /mnt/install ] && mkdir /mnt/install
declare -a drs=( /dev /dev/pts /dev/shm /install /proc /run /sys )
export drs
for i in ${drs[@]}; do
    mount --bind $i /mnt$i
done

chmod -R g-rwx,o-rwx /mnt/boot
#chroot /mnt
