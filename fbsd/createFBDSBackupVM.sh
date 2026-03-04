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
app_part=1
swap_sz=

ERR_DEVC=1
ERR_BACK=2
ERR_NOSN=3
ERR_PART=4
ERR_POOL=5
ERR_SNAP=6
ERR_CUSR=7
ERR_MOUT=8
ERR_PEFI=9

computeZFS(){
    gpart show $1 | grep '\- free \-' | tail -1 | awk "{print \$$2}"	
}
computeZFSSize(){
	computeZFS $1 2
}
findPartByLabel(){
	gpart show -l $1 | grep $2 | awk '{print $3}'
}
lastPartId(){
	gpart show $1 | grep -v "\($1\|\- free \-\)" | grep "\S\{1,\}" | tail -1 | awk '{print $3}'
}

createPartTable(){
    echo gpart create -s GPT $dvc
	echo gpart add -t efi -l efiboot0 -b 40 -s 260M $dvc
}
partStart(){
    computeZFS $1 1
}
createPartIFNEXT(){
	if ! gpart show -l $1 | grep $3 ; then
		part_start=$(partStart $1 )
		[ -n "$5" ] && part_start=$(($part_start+$5))
		gpart add -t $4 -l $3 -b $part_start -s $2 $1
	fi
}
addPartFBSD(){
	p_id=2
	if [ "$app_part" = "0" ]; then
		p_id=$(findPartByLabel $dvc gptboot0 )
		[ -z "$p_id" ] && p_id=$((1+$(lastPartId $dvc )))
	fi
	createPartIFNEXT $dvc 1024 gptboot0 freebsd-boot
    createPartIFNEXT $dvc $swap_sz swap0 freebsd-swap 984
    createPartIFNEXT $dvc $(($(computeZFSSize $dvc )-2008)) zfs0 freebsd-zfs
    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i $p_id $dvc

}
listZFSFSs(){
	fs_type=$3
	[ -n "$fs_type" ] && fs_type="-t $fs_type"
	for i in $(zfs list -r $fs_type $1 | awk '{print $1}' | grep -v "$2" ); do
		echo $i
	done
}
createPool(){
	if [ "$app_part" = "1" ]; then
		p_id=4
	else
		p_id=$(findPartByLabel $dvc zfs0 )
#		[ -z "$p_id" ] && p_id=$((3+$(lastPartId $dvc )))
	fi
    zpool create $pool_name /dev/${dvc}p$p_id
}
copyBackup(){
	bu=$(echo $backup | sed 's=/=\\/=g' )
    for i in $(listZFSFSs $back_pool NAME snapshot | grep $snap_name ); do
	    trg=$(echo $i | sed "s/$bu//g" | sed 's/@.\{1,\}//g' )
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
    for i in $(listZFSFSs $pool_name "\($pool_name\$\|NAME\)" | sort -r ); do
        if [ "$i" = "$pool_name/root/ROOT/default" ]; then
            zfs set -u mountpoint=/ $i
        else
            zfs set -u mountpoint=$(echo $i | sed "s=$pool_name/root==g" ) $i
        fi
    done

}

prepareEFI(){
    if [ "app_part" = "1" ]; then
		newfs_msdos -F 32 -c 1 /dev/${dvc}p1
	else
		fs_tab=/$pool_name/root/ROOT/default/etc/fstab
		# correct efi entry
		sed -i'' -e "s=$(grep efi $fs_tab | awk '{print $1}' )=/dev/${dvc}p1=g" $fs_tab
		# correct swap entry
		sed -i'' -e "s=$(grep swap $fs_tab | awk '{print $1}' )=/dev/${dvc}p$(findPartByLabel $dvc swap0 )=g" $fs_tab
		
	fi
    mount -t msdosfs /dev/${dvc}p1 /mnt
	dr=/mnt/efi
    [ ! -d $dr/boot ] && mkdir -p /mnt/efi/boot
    [ ! -d $dr/freebsd ] && mkdir /mnt/efi/freebsd
    cp /boot/efi/efi/boot/bootx64.efi /mnt/efi/boot
    cp /boot/efi/efi/freebsd/loader.efi /mnt/efi/freebsd
    echo "rootdev=zfs:$pool_name/root/ROOT/default:" >> /mnt/efi/freebsd/loader.env
}

umountClone(){
	for i in $(mount | grep $pool_name | awk '{print $3}' | sort -r | grep -v $pool_name\$ ); do
		zfs umount $i
	done
	zpool export $pool_name
}

helptxt(){
    cat << EOH
 $0 [Option] DEVICE BACKUP-POOL SNAP-SHOT [NEW-POOL] [SWAP-SIZE]
 
 	1) sets up a new GPT type disk with zfs as fourth partition, or

	2) appends FreeBSD partitions behind last non-free space, note that
	  disk size may cause failure (e.g. not enough space)

	Then it copies all snapshots from
	BACKUP-POOL to NEW-POOL, corrects /usr or /var if needed, includes EFI loaders and
        loader env file in EFI system partition
 
 Attention: this script will permanently change the disk/block device, take care to
			NOT override needed data
 
 Parameters:
        DEVICE      block device to recreate from backup, e.g. nda0, ada1,...
        BACKUP-POOL zfs backup dataset to recover, e.g. backup_pool/data
	SNAP-SHOT   backup snapshot name, e.g. @recent, @20250101,...
        NEW-POOL    zpool backup being newly create, default is zclone
        SWAP-SIZE   swap size string, e.g. 512M, 4G, ..., defaults to 2G
 Options:
        -h/--help   print this message
	-a/--append only append new FreeBSD partitions,
		    does NOT create new partition table
 Exit codes:
		0 - setup succeeded
		$ERR_DEVC - no device given,
		$ERR_BACK - no backup dataset given
		$ERR_NOSN - no snapshot given
		$ERR_PART - partitioning failed
		$ERR_POOL - pool creation failed
		$ERR_SNAP - backup clone failed
		$ERR_CUSR - correct /usr failed
		$ERR_MOUT - mount adjustments failed
		$ERR_PEFI - prepping EFI system partition or adjusting fstab failed
		
EOH
}
main(){
    case $1 in
    '-h'|'--help') helptxt && return 0
    ;;
	'-a'|'--append') app_part=0
	;;
    esac
	shift
    dvc=$1
    backup=$2
	snap_name=$3
	back_pool=$(echo $backup | cut -d/ -f1 )
    pool_name=${4:-zclone}
	swap_sz=${5:-2G}
    [ -z "$dvc" ] && echo no root block device given - aborting && return $ERR_DEVC
    [ -z "$backup" ] && echo no backup pool given - aborting && return $ERR_BACK
    [ -z "$snap_name" ] && echo no backup snapshot given - aborting && return $ERR_NOSN
    
	if [ "$app_part" = "1" ]; then
		createPartTable || return $ERR_PART
	fi
	addPartFBSD || return $ERR_PART
    createPool || return $ERR_POOL
    copyBackup || return $ERR_SNAP
    correctUSR || return $ERR_CUSR
    adjustMounts || return $ERR_MOUT
    prepareEFI || return $ERR_PEFI
	umountClone
}

main $@
