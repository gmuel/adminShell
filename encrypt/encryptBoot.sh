#!/bin/bash
helptxt(){
  cat << EOF
    $0 BOOT_DVC [FS_TYPE]
      Encryption facility script
      
 Usage:
      createLuks1Boot:
      
        Copies BOOT_DVC to local folder, encrypts BOOT_DVC as luks1
        with copies the original content back to said device
        on file system FS_TYPE (default: ext4)
        NOTE - the key file used will be automatically created 
        
        BOOT_DEVICE - block device containing the boot partition (e.g. /dev/sda1, /dev/nvme1np1 )
        FS_TYPE     - file system type of the boot partition, NOTE should match the entry in /etc/fstab
      
        ATTENTION:  this will replace your previous boot partition, any errors can render your system
                    unbootable. 
      
EOF
  [ -z "$1" ] && return 0 || return $1
}
[[ "$1" == "-h" || "$1" == "--help" ]] && helptxt 0
btDvc=$1
# kyfl=$2
[ -n "$2" ] && fs=$2 || fs=ext4
umountBoot(){
  if mount | grep "/boot " ; then
    mount | grep "/boot/efi " && umount /boot/efi
    umount /boot
  fi
}
mountBoot(){
  mount -v /boot
  [ ! -d /boot/efi ] && mkdir /boot/efi
  [ -n "$1" ] && mount -v /boot/efi
}
mkfsAndCopy(){
  uuid=$1
  fs=$2
  [ -z "$fs" ] && fs=ext4
  mkfs.$fs -m0 /dev/mapper/boot_crypt
  refreshFSTab $3
  mountBoot
  tar -C /boot --acls --xattrs -xf /tmp/boot.tar
}
updateInitNGrub(){
  mount -a
  update-initramfs -u -k all
  update-grub
  grub-install
}
includeKey(){
  sed -i.1 "s/\(UUID=$1\) none \(luks\(,discard\)\?\)/\1 ${kyfl//'/'/'\/'} \2/g" /etc/crypttab
}
createLuks1Boot(){
  #echo   mount -o remount,ro /boot
  # mount -o remount,ro /boot
  runCmd mount -o remount,ro /boot && \
    runCmd "mount | grep /boot/efi && umount /boot/efi" && \
    runCmd install -m0600 /dev/null /tmp/boot.tar && \
    runCmd tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar . && \
    runCmd umountBoot && \
    runCmd dd if=/dev/urandom of=\$btDvc bs=1M status=none # && \
    runCmd cryptsetup luksFormat --type luks1 $btDvc && \
    runCmd uuid=$(blkid -o value -s UUID $btDvc) && \
    kyfl=/root/.keys/.${uuid}.key && \
    runCmd dd if=/dev/urandom of=$kyfl bs=512 count=8 && \
    runCmd chmod 0600 $kyfl && \
    runCmd cryptsetup luksAddKey $btDvc $kyfl && \
    runCmd addKey && \
    runCmd cryptdisks_start boot_crypt && \
    runCmd mkfsAndCopy $uuid $fs && \
    runCmd updateInitNGrub
#  echo install -m0600 /dev/null /tmp/boot.tar
#  install -m0600 /dev/null /tmp/boot.tar
#  echo tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar .
#  tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar .
#  echo umountBoot
#  umountBoot
#  echo dd if=/dev/urandom of=\$btDvc bs=1M status=none
#  dd if=/dev/urandom of=$btDvc bs=1M status=none
#  echo cryptsetup luksFormat --type luks1 $btDvc
#  cryptsetup luksFormat --type luks1 $btDvc
#  echo cryptsetup luksAddKey $btDvc $kyfl
#  cryptsetup luksAddKey $btDvc $kyfl
#  echo "uuid=\"\$(blkid -o value -s UUID \$btDvc) \""
#  uuid="$(blkid -o value -s UUID $btDvc)"
#  echo "echo \"boot_crypt UUID=$uuid $kyfl luks,discard,key-slot=1 \"| tee -a /etc/crypttab"
#  echo "boot_crypt UUID=$uuid $kyfl luks,discard,key-slot=1" | tee -a /etc/crypttab
#  echo cryptdisks_start boot_crypt
#  cryptdisks_start boot_crypt
#  echo mkfsAndCopy $uuid $fs
#  mkfsAndCopy $uuid $fs
}

runCmd(){
    echo "$@"
    eval $@
}
removeKey(){
    grep boot_crypt /etc/crypttab && sed -i "s/boot_crypt UUID=[a-f0-9\-]\+.\+//g" /etc/crypttab
}
addKey(){
    removeKey
    echo boot_crypt UUID=$uuid $kyfl luks,discard,key-slot=1 | tee -a /etc/crypttab
}

refreshFSTab(){
    [[  "$1" == "rollback" ]] && uuid1=$(blkid -s UUID -o value /dev/mapper/boot_crypt ) || uuid1=$((blkid -s UUID -o value $btDvc ))
    sed -i "s/\(${btDvc//'/'/'\/'}\|UUID=[a-f0-9\-]\+\)\( \/boot .\+\)/UUID=$uuid1\2/g" /etc/fstab
}

rollback(){
  uuid=$1
  fs=$2
  [ -z "$fs" ] && fs=ext4  
  umountBoot
  cryptdisks_stop boot_crypt
  mkfsAndCopy $uuid $fs rollback
  removeKey
  updateInitNGrub
}
