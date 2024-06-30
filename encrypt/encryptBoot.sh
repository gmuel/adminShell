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
  return $1
}
[[ "$1" == "-h" || "$1" == "--help" ]] && helptxt 0
btDvc=$1
kyfl=$2
[ -z "$3" ] && fs=$3 || fs=ext4
umountBoot(){
  if mount | grep boot_crypt; then
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
  sed -i "s/\(UUID=$uuid\) none luks\(,discard\)\?/\1 $kyfl \2/g" /etc/crypttab
}
createLuks1Boot(){
  mount -o remount,ro /boot
  install -m0600 /dev/null /tmp/boot.tar
  tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar .
  umountBoot
  dd if=/dev/urandom of=/dev/sda1 bs=1M status=none
  cryptsetup luksFormat --type luks1 $btDvc
  cryptsetup luksAddKey $btDvc $kyfl
  uuid="$(blkid -o value -s UUID $btDvc)"
  echo "boot_crypt UUID=$uuid $kyfl luks,discard,key-slot=1" | tee -a /etc/crypttab
  cryptdisks_start boot_crypt
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
