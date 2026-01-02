#!/bin/bash


helptxt(){
    cat << EOH
$0 [options] DISK_DEVICE [LVM_FLAGS [SWAP_SIZE]]

    Create a two partition disk on DISK_DEVICE with the second partition as a crypto_LUKS part(!)
    
    1st partition - EFI system partition (size 2GB)
    2nd partition - Root file system either as BTRFS or LVM (VG: main_vol) with two independent BTRFSs (root, home)
                    The latter use case is for reinstall without having to copy the home vol/partition from backup
                    NOTE: this will encrypt the second partition via cryptsetup, this step is NOT reversible
                    NOTE: a password will be asked - do not lose/forget or the system will be unbootable

    Arguments
        DISK_DEVICE -   unpartitioned blockdevice to install system on, i.e. /dev/nvme0n1, /dev/sdb,... 
                        required argument
        LVM_FLAGS   -   'nolvm' use this flag as second argument to create a single BTRFS fs on second partition
                        'size' integer indicator for volume size of root volume  in GB (/dev/mapper/main_vol-root), default is 16GB
        SWAP_SIZE   -   swap size,  sum of LVM_FLAGS and SWAP_SIZE must not exceed disk device size 

    Options:
        -h/--help       print this message
        -v/--version    print version string

    Usage:
        $0 /dev/sda nolvm   ->  create encrypted root with single BTRFS partition
        $0 /dev/sda 16      ->  create encrypted root with LVM on top, root volume with size 16GB
        $0 /dev/sda 16 4    ->  create encrypted root with LVM on top, root volume with size 16GB and 4G swap volume
EOH
}
version(){
    echo Version 0.9.0
}

min(){
    [ "$1" <= "$2" ] && echo $1 || echo $2
}

[ -z "$1" ] && echo ERROR: no DISK_DEVICE given - aborting && echo type $0 --help for info && exit 1
[[ "$1" == "-h" || "$1" == "--help" ]] && helptxt && exit 0
[[ "$1" == "-v" || "$1" == "--version" ]] && helptxt && exit 0


rtd=$1
efi=${rtd}
dvc=${rtd}

if echo $rtd | grep nvme ; then
    efi=${efi}p
    dvc=${dvc}p
fi
efi=${efi}1
dvc=${dvc}2


parted -s ${rtd} mklabel gpt

parted -s -a optimal ${rtd} mkpart ESP fat32 1MiB 2048MiB

mkfs.vfat -F32 ${efi} 

parted -s ${rtd} set 1 boot on

parted -s  -a optimal ${rtd} mkpart primary 2049MiB 100%

cryptsetup -v --cipher aes-xts-plain64 --key-size 512 --hash sha512 --pbkdf pbkdf2 --pbkdf-force-iterations 100000 --use-random luksFormat --type luks2 ${dvc} 
uuid=$(blkid -s UUID -o value $dvc )
lxid=luks-$uuid
cryptsetup luksOpen ${dvc}  $lxid
dmd=/dev/mapper/$lxid
#mkfs.btrfs -L root $dmd
if [[ "$2" == "nolvm" ]]; then
    mkfs.btrfs -L root $dmd
else
    lz=$2
    
    pvcreate $dmd
    vgcreate main_vol $dmd
    sz=$(vgdisplay | grep 'VG Size' | sed "s/\s\+/ /g" | cut -d' ' -f4 | sed "s/\([0-9]\+\)\..\+/\1/g" )
    [ -z "$lz" ] && lz=$(min 16 $(($sz/4)) )
    lvcreate -L ${lz}G -n root main_vol
    if [ -n "$3" ] && echo $3 | grep -q "^[0-9]\+\$" && [ "$(($sz-$lz-$3))" -gt "0" ]; then
        lvcreate -L ${3}G -n swap main_vol
        lvcreate -L $(($sz-$lz-$3))G -n home main_vol
    else
        lvcreate -L $(($sz-$lz))G -n home main_vol
    fi
fi
#mkdir -p /boot/efi/EFI/Boot
apt-cdrom add /dev/sr0
apt update

apt install -y efibootmgr binutils systemd-boot systemd-boot-efi zstd gawk

