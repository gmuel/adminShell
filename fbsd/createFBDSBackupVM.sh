#!/bin/sh

# taken from 	https://docs.freebsd.org/en/books/handbook/geom/
#				https://docs.freebsd.org/en/books/handbook/zfs/
#				https://www.freebsd.org/cgi/man.cgi
#				https://forums.freebsd.org/threads/how-to-do-a-full-system-backup-of-freebsd-so-i-can-boot-from-it-if-my-current-system-fails.76474/


dvc=
backup=
pool_name=
back_pool=
snap_name=

ERR_DEVC=1
ERR_BACK=2
ERR_PART=3
ERR_POOL=4
ERR_SNAP=5
ERR_CUSR=6
ERR_MOUT=7
ERR_PEFI=8
ERR_NOSN=9

computeZFSSize(){
    gpart show $1 | grep '\- free \-' | tail -1 | awk '{print $2}'
}

createPartTable(){
    gpart create -s GPT $dvc
    gpart add -t efi -l efiboot0 -b 40 -s 260M $dvc
    gpart add -t freebsd-boot -l gptboot0 -b 532520 -s 1024 $dvc
    gpart add -t freebsd-swap -l swap0 -b 534528 -s 2G $dvc
    gpart add -t freebsd-zfs -l zfs0 -b 4728832 -s $(($(computeZFSSize $dvc )-2008)) $dvc

    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 2 $dvc

    newfs_msdos -F 32 -c 1 /dev/${dvc}p1
}
createPool(){
    zpool create $pool_name /dev/${dvc}p4
}
copyBackup(){
    for i in $(zfs list -rt snapshot $back_pool | awk '{print $1}' | grep $snap_name | grep -v NAME ); do
	    trg=$(echo $i | sed "s/$backup//g" | sed 's/@.\{1,\}//g' )
	    zfs send $i | zfs receive $pool_name/root$trg
    done
}

correctUSR(){
    [ ! -d $pool_name/root/usr/bin ] && cp -vrp /$pool_name/root/ROOT/default/usr/* /$pool_name/root/usr \
        && rm -vrf /$pool_name/root/ROOT/default/usr/*
    [ ! -d $pool_name/root/var/tmp ] && cp -vrp /$pool_name/root/ROOT/default/var/* /$pool_name/root/var \
        && rm -vrf /$pool_name/root/ROOT/default/var/*
}

adjustMounts(){
    for i in $(zfs list -r $pool_name | awk '{print $1}' | sort -r | grep -v "\($pool_name\$\|NAME\)"); do
        if [ "$i" = "$pool_name/root/ROOT/default" ]; then
            zfs set mountpoint=/ $i
        else
            zfs set mountpoint=$(echo $i | sed "s/$pool_name\/root//g" ) $i
        fi
    done

}

prepareEFI(){
    mount -t msdosfs /dev/${dvc}p1 /mnt
    mkdir -p /mnt/efi/boot
    mkdir /mnt/efi/freebsd
    cp /boot/efi/efi/boot/bootx64.efi /mnt/efi/boot
    cp /boot/efi/efi/freebsd/loader.efi /mnt/efi/freebsd
    echo "rootdev=zfs:$pool_name/root/ROOT/default:" >> /mnt/efi/freebsd/loader.env
}

helptxt(){
    cat << EOH
 $0 [Option] DEVICE BACKUP-POOL SNAP-SHOT [NEW-POOL]
 
 sets up a new GPT type disk with zfs as fourth partition, copies all snapshots from
 BACKUP-POOL to NEW-POOL, corrects /usr or /var if needed, includes EFI loaders and
 loader env file in EFI system partition
 
 Attention: this script will permanently change the disk/block device, take care to
			NOT override needed data
 
 Parameters:
        DEVICE      block device to backup to, e.g. nda0, ada1,...
        BACKUP-POOL zfs backup dataset to recover, e.g. backup_pool/data
		SNAP-SHOT	backup snapshot name, e.g. @recent, @20250101,...
        NEW-POOL    zpool backup being newly create, default is zclone
 Options:
        -h/--help   print this message

 Exit codes:
		0 - setup succeeded
		$ERR_DEVC - no device given,
		$ERR_BACK - no backup dataset given
		$ERR_PART - partitioning failed
		$ERR_POOL - pool creation failed
		$ERR_SNAP - backup clone failed
		$ERR_CUSR - correct /usr failed
		$ERR_MOUT - mount adjustments failed
		$ERR_PEFI - prepping EFI system partition failed
		$ERR_NOSN - no snapshot given
		
EOH
}
main(){
    case $1 in
    '-h'|'--help') helptxt && return 0
    ;;
    esac
    dvc=$1
    backup=$2
	snap_shot=$3
	back_pool=$(echo $backup | cut -d/ -f1 )
    pool_name=${4:-zclone}
    [ -z "$dvc" ] && echo no root block device given - aborting && return $ERR_DEVC
    [ -z "$backup" ] && echo no backup pool given - aborting && return $ERR_BACK
    [ -z "$snap_shot" ] && echo no backup snapshot given - aborting && return $ERR_NOSN
    createPartTable || return $ERR_PART
    createPool || return $ERR_POOL
    copyBackup || return $ERR_SNAP
    correctUSR || return $ERR_CUSR
    adjustMounts || return $ERR_MOUT
    prepareEFI || return $ERR_PEFI
}

main $@
