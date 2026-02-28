#!/bin/sh

dvc=
backup=
pool_name=
computeZFSSize(){
    gpart show $1 | grep '\- free \-' | tail -1 | awk '{print $2}'
}

createPartTable(){
    gpart create -s GPT $dvc
    gpart add -t efi -l efiboot0 -b 40 -s 260M $dvc
    gpart add -t freebsd-boot -l gptboot0 -b 532520 -s 1024 $dvc
    gpart add -t freebsd-swap -l swap0 -b 534528 -s 2G $dvc
    gpart add -t freebsd-zfs -l zfs0 -b 4728832 -s $(($(computeZFSSize )-2008)) $dvc

    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 2 $dvc

    newfs_msdos -F 32 -c 1 /dev/${dvc}p1
}
createPool(){
    zpool create $pool_name /dev/${dvc}p4
}
copyBackup(){
    for i in $(zfs list -rt snapshot $backup | awk '{print $1}' | grep -v NAME ); do
	    trg=$(echo $i | sed "s/$backup\/data//g" | sed 's/@.\{1,\}//g' )
	    zfs send $i | zfs receive $pool_name/root$trg
    done
}

correctUSR(){
    [ ! -d $pool_name/root/usr/bin ] && cp -vrp /$pool_name/root/ROOT/default/usr/* /$pool_name/root/usr \
        && rm -vrf /$pool_name/root/ROOT/default/usr/*
    [ ! -d $pool_name/root/var/tmp ] && cp -vrp /$pool_name/root/ROOT/default/var/* /$pool_name/root/var \
        && rm /$pool_name/root/ROOT/default/var/*
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
 $0 [Option] DEVICE BACKUP-POOL [NEW-POOL]
 
 sets up a new GPT type disk with zfs as fourth partition, copies all datasets from
 BACKUP-POOL to NEW-POOL, corrects /usr or /var if needed, includes EFI loaders and
 loader env file in EFI system partition
 
 Parameters:
        DEVICE      block device to backup to, e.g. nda0, ada1,...
        BACKUP-POOL zpool backup to recover
        NEW-POOL    zpool backup being newly create, default is zclone
 Options:
        -h/--help   print this message
EOH
}
main(){
    case $1 in
    '-h'|'--help') helptxt && return 0
    ;;
    esac
    dvc=$1
    backup=$2
    pool_name=${3:-zclone}
    [ -z "$dvc" ] && echo no root block device given - aborting && return 1
    [ -z "$backup" ] && echo no backup pool given - aborting && return 2
    createPartTable
    createPool
    copyBackup
    correctUSR
    adjustMounts
    prepareEFI
}

main $1 $2 $3
