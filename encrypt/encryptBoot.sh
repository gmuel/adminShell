#!/bin/bash
helptxt(){
  cat << EOF
    $0 BOOT_DEVICE KEY_FILE [FS_TYPE]
      Copies BOOT_DVC to local folder, encrypts BOOT_DIVCE as luks1
      with a KEY_FILE and copies the original content back to said device
      on file system FS_TYPE (default: ext4)
      
      BOOT_DEVICE - block device containing the boot partition (e.g. /dev/sda1, /dev/nvme1np1 )
      KEY_FILE    - common key file for boot and root partition
      FS_TYPE     - file system type of the boot partition, NOTE should match the entry in /etc/fstab
      
EOF
  [ -z "$1" ] && return 0 || return $1
}
[[ "$1" == "-h" || "$1" == "--help" ]] && helptxt 0
btDvc=$1
kyfl=$2
[ -z "$3" ] && fs=$3 || fs=ext4
umountBoot(){
  if mount | grep "boot\(_crypt\)\?" ; then
    mount | grep efi && umount /boot/efi
    umount /boot
  fi
}
mountBoot(){
  mount -v /boot
  [ -d /boot/efi ] && mount -v /boot/efi
}
mkfsAndCopy(){
  uuid=$1
  fs=$2
  [ -z "$fs" ] && fs=ext4
  mkfs.$fs -m0 -U $uuid /dev/mapper/boot_crypt
  mountBoot
  tar -C /boot --acls --xattrs -xf /tmp/boot.tar
}
updateInitNGrub(){
  update-initramfs -u
  update-grub
  grub-install
}
includeKey(){
  sed -i.1 "s/\(UUID=$1\) none \(luks\(,discard\)\?\)/\1 ${kyfl//'/'/'\/'} \2/g" /etc/crypttab
}
createLuks1Boot(){
  echo   mount -o remount,ro /boot
  mount -o remount,ro /boot
  echo install -m0600 /dev/null /tmp/boot.tar
  install -m0600 /dev/null /tmp/boot.tar
  echo tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar .
  tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar .
  echo umountBoot
  umountBoot
  echo dd if=/dev/urandom of=\$btDvc bs=1M status=none
  dd if=/dev/urandom of=$btDvc bs=1M status=none
  echo cryptsetup luksFormat --type luks1 $btDvc
  cryptsetup luksFormat --type luks1 $btDvc
  echo cryptsetup luksAddKey $btDvc $kyfl
  cryptsetup luksAddKey $btDvc $kyfl
  echo "uuid=\"\$(blkid -o value -s UUID \$btDvc) \""
  uuid="$(blkid -o value -s UUID $btDvc)"
  echo "echo \"boot_crypt UUID=$uuid $kyfl luks,discard,key-slot=1 \"| tee -a /etc/crypttab"
  echo "boot_crypt UUID=$uuid $kyfl luks,discard,key-slot=1" | tee -a /etc/crypttab
  echo cryptdisks_start boot_crypt
  cryptdisks_start boot_crypt
  echo mkfsAndCopy $uuid $fs
  mkfsAndCopy $uuid $fs
}

rollback(){
  uuid=$1
  fs=$2
  [ -z "$fs" ] && fs=ext4  
  umountBoot
  cryptdisks_stop boot_crypt
  mkfsAndCopy $uuid $fs
  updateInitNGrub
}
