dvc=$1
sz=$2
backup=$3

[ -z "$dvc" ] && echo no root block device given - aborting && return 1
[ -z "$sz" ] && echo no zfs size given - aborting && return 2

gpart create -s GPT $dvc
gpart add -t efi -l efiboot0 -b 40 -s 260M $dvc
gpart add -t freebsd-boot -l gptboot0 -b 532520 -s 1024 $dvc
gpart add -t freebsd-swap -l swap0 -b 534528 -s 2G $dvc
gpart add -t freebsd-zfs -l zfs0 -b 4728832 -s $sz $dvc

gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 2 $dvc

newfs_msdos -F 32 -c 1 /dev/${dvc}p1

zpool create zclone /dev/${dvc}p4

for i in $(zfs list -rt snapshot $backup | awk '{print $1}' | grep -v NAME ); do
	trg=$(echo $i | sed "s/$backup//g" | sed "s/@.\+//g" )
	zfs send $i | zfs receive zclone/root$trg
done


