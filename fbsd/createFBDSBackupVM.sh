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
labl_id=0
ecrypt=1
root_labl=
root_part=
root_ds=
swap_pt=

ERR_DEVC=1
ERR_BACK=2
ERR_NOSN=3
ERR_PART=4
ERR_POOL=5
ERR_SNAP=6
ERR_CUSR=7
ERR_MOUT=8
ERR_PEFI=9



helptxt(){
    cat << EOH
 $0 [Option] DEVICE BACKUP-DS SNAP-SHOT [NEW-POOL] [SWAP-SIZE]
 
 	1) single boot - sets up a new GPT type disk with zfs as fourth partition, or

	2) dual boot - appends FreeBSD partitions behind last non-free space, note that
	  disk size may cause failure (e.g. not enough space),
	  NOTE: this mode requires a multi boot loader(!)
	  
	3) encrypts both root file system and swap in either case (single or dual boot)

	Then it copies all snapshots from
	BACKUP-DS to NEW-POOL, corrects /usr or /var if needed, includes EFI loaders and
        loader env file in EFI system partition
 
 Attention: this script will permanently change the disk/block device, take care to
			NOT override needed data
 
 Parameters:
        DEVICE      block device to recreate from backup, e.g. nda0, ada1,...
        BACKUP-DS   zfs backup dataset to recover, e.g. backup_pool/data
	SNAP-SHOT   backup snapshot name, e.g. @recent, @20250101,...
        NEW-POOL    zpool being newly create, default is zclone
        SWAP-SIZE   swap size string, e.g. 512M, 4G, ..., defaults to 2G
 Options:
        -h/--help    print this message
	-a/--append  only append new FreeBSD partitions,
		     does NOT create new partition table
        -e/--encrypt encrypt zpool partition with geli util
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
    gpart create -s GPT $dvc
	gpart add -t efi -l efiboot0 -b 40 -s 260M $dvc
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
		p_id=$(findPartByLabel $dvc gptboot$labl_id )
		[ -z "$p_id" ] && p_id=$((1+$(lastPartId $dvc )))
	fi
	createPartIFNEXT $dvc 1024 gptboot$labl_id freebsd-boot
    createPartIFNEXT $dvc $swap_sz swap$labl_id freebsd-swap 984
    createPartIFNEXT $dvc $(($(computeZFSSize $dvc )-2008)) $root_labl freebsd-zfs
    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i $p_id $dvc
}
listZFSDSs(){
	fs_type=$3
	[ -n "$fs_type" ] && fs_type="-t $fs_type"
	for i in $(zfs list -r $fs_type $1 | awk '{print $1}' | grep -v "$2" ); do
		echo $i
	done
}
createPool(){
	if [ "$app_part" = "1" ] && [ $ecrypt = 1 ]; then
		p_id=4
	else
		p_id=$(findPartByLabel $dvc $root_labl )
	fi
	zfs_dvc=/dev/$root_part
	[ $ecrypt = 0 ] &&  zfs_dvc=${zfs_dvc}.eli
    zpool create $pool_name $zfs_dvc
}
copyBackup(){
    for i in $(listZFSDSs $back_pool NAME snapshot | grep $snap_name | grep -v $backup$snap_name ); do
	    trg=$(echo $i | sed "s=$backup==g" | sed 's/@.\{1,\}//g' )
	    zfs send $i | zfs receive $pool_name$trg
    done
}

correctUSR(){
    [ ! -d /$pool_name/usr/bin ] && cp -vrp /$root_ds/usr/* /$pool_name/usr \
        && rm -vrf /$root_ds/usr/*
    [ ! -d /$pool_name/var/lib ] && cp -vrp /$root_ds/var/* /$pool_name/var \
        && rm -vrf /$root_ds/var/*
	if ! ls -l /$pool_name/var/ | grep tmp | grep rwt; then
		chmod 1777 /$pool_name/var/tmp
	fi
	if ! ls -l /$root_ds | grep tmp | grep rwt; then
		chmod 1777 /$root_ds/tmp
	fi
}

adjustMounts(){
    for i in $(listZFSDSs $pool_name "NAME" | sort -r ); do
        if [ "$i" = "$root_ds" ]; then
            zfs set -u mountpoint=/ $i
        elif [ "$i" = "$pool_name" ] || [ "$i" = "$pool_name/ROOT" ]; then
            zfs set -u mountpoint=none $i
        else
            zfs set -u mountpoint=$(echo $i | sed "s=$pool_name==g" ) $i
        fi
    done

}

prepareEFI(){
    fs_tab=/$root_ds/etc/fstab
    if [ $app_part = 1 ]; then
		newfs_msdos -F 32 -c 1 /dev/${dvc}p1
	else
		# correct efi entry
		sed -i'' -e "s=$(grep efi $fs_tab | awk '{print $1}' )=/dev/${dvc}p1=g" $fs_tab
		# correct swap entry
		sed -i'' -e "s=$(grep swap $fs_tab | awk '{print $1}' )=$swap_pt=g" $fs_tab
		
	fi
	[ $ecrypt = 0 ] && sed -i'' -e "s=$(grep swap $fs_tab | awk '{print $1}' )=${swap_pt}.eli=g" $fs_tab
    mount -t msdosfs /dev/${dvc}p1 /mnt
	dr=/mnt/efi
    [ ! -d $dr/boot ] && mkdir -p /mnt/efi/boot
    [ ! -d $dr/freebsd ] && mkdir /mnt/efi/freebsd
    cp /boot/efi/efi/boot/bootx64.efi /mnt/efi/boot
    cp /boot/efi/efi/freebsd/loader.efi /mnt/efi/freebsd
    echo "rootdev=zfs:$root_ds:" >> /mnt/efi/freebsd/loader.env
}

umountClone(){
	for i in $(mount | grep $pool_name | awk '{print $3}' | sort -r | grep -v $pool_name\$ ); do
		zfs umount $i
	done
	zpool export $pool_name
}

prepareEcrypt(){
    echo kldload geom_eli
    ky_fl=/root/.keys/${root_part}.key
    encrypt.sh $root_part $ky_fl && \
    geli attach /dev/$root_part
    geli onetime -d $swap_pt
}

finalizeEcrypt(){
    new_root=/$root_ds
    mv /root/.keys/ ${new_root}/boot
    cat << EOI >> ${new_root}/boot/loader.conf
geom_eli_load="YES"
vfs.root.mountfrom="zfs:$root_ds"
EOI
    cat << EOI >> ${new_root}/etc/rc.conf
geli_device="$root_part"
geli_${root_part}_flags="-k /boot/.keys/${root_part}.key"
EOI
    dr=/$pool_name/root/var/backups
    [ ! -d $dr ] && mkdir -p $dr
    mv /var/backups/${root_part}.eli $dr
}

main(){    
    case $1 in
    '-h'|'--help') helptxt && return 0
    ;;
	'-a'|'--append')
	    app_part=0
	    shift
	    main $@
	    return $?
	;;
	'-e'|'--encrypt') 
	    ecrypt=0
	    root_labl=geli$labl_id
	    shift
	    main $@
	    return $?
	;;
    esac
#	 echo $1 | grep -q "\-\([a-zA-z]\|\-[a-zA-z]\{1,\}\)"; then
#	    main $@
#	    return $?
#	fi
    dvc=$1
    backup=$2
	snap_name=$3
	back_pool=$(echo $backup | cut -d/ -f1 )
    pool_name=${4:-zclone}
	swap_sz=${5:-2G}
	root_labl=${root_labl:-zfs$labl_id}
    [ -z "$dvc" ] && echo no root block device given - aborting && return $ERR_DEVC
    [ -z "$backup" ] && echo no backup pool given - aborting && return $ERR_BACK
    [ -z "$snap_name" ] && echo no backup snapshot given - aborting && return $ERR_NOSN
    
	if [ "$app_part" = "1" ]; then
	    echo "Creating new partition table on disk $dvc"
		createPartTable || return $ERR_PART
	fi
	echo "Adding default partitions.."
	addPartFBSD || return $ERR_PART
	root_part=${dvc}p$(findPartByLabel $dvc $root_labl )
	swap_pt=/dev/${dvc}p$(findPartByLabel $dvc swap$labl_id )
	if [ $ecrypt = 0 ]; then
	    echo "Preparing encrypted provider $root_part"
	    prepareEcrypt 
	fi
	echo "Creating new pool $pool_name"
    createPool || return $ERR_POOL
    echo "Restoring new pool $pool_name from $backup"
    copyBackup || return $ERR_SNAP
    root_ds=$pool_name/ROOT/default
    echo "Testing if /usr-correction required"
    correctUSR || return $ERR_CUSR
    echo "Adjusting zfs mountpoints"
    adjustMounts || return $ERR_MOUT
    echo "Setting up EFI"
    prepareEFI || return $ERR_PEFI
    if [ $ecrypt = 0 ]; then
        echo "Correcting boot parameters"
	    finalizeEcrypt
	fi
	umountClone && [ $ecrypt = 0 ] && geli detach ${root_part}.eli
}

main $@
