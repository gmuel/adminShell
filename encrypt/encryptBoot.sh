#!/bin/bash
helptxt(){
  cat << EOF
    $0 [options] BOOT_DVC [FS_TYPE]
      Boot device encryption source script
      
 Usage:
      createLuks1Boot
      
        Copies BOOT_DVC to local folder, encrypts BOOT_DVC as luks1
        with copies the original content back to said device
        on file system FS_TYPE (default: ext4)
        NOTE - the key file used will be automatically created 
        
        Options       -h/--help print this message
        
        BOOT_DEVICE - block device containing the boot partition (e.g. /dev/sda1, /dev/nvme1np1 )
        FS_TYPE     - file system type of the boot partition, NOTE should match the entry in /etc/fstab
      
        ATTENTION:  this will replace your previous boot partition, any errors can render your system
                    unbootable. A backup file is created called /tmp/boot.tar. The rollback requires
                    this file, the original boot device (first arg) and file system type
      
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
  fs=$1
  dvc=$2
  [ -z "$fs" ] && fs=ext4
  mkfs.$fs -m0 $dvc
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
    runCmd mkfsAndCopy $fs /dev/mapper/boot_crypt && \
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
    [[  "$1" == "rollback" ]] && uuid1=$(blkid -s UUID -o value $btDvc ) || uuid1=$(blkid -s UUID -o value /dev/mapper/boot_crypt )
    sed -i "s/\(${btDvc//'/'/'\/'}\|UUID=[a-f0-9\-]\+\)\( \/boot .\+\)/UUID=$uuid1\2/g" /etc/fstab
}

rollback(){
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EOH
   rollback - rollback encryption process, unmounts newly create boot and encrypts it,
              writes new FS to boot device (btDvc, aka original device), updates fstab
              and removes the boot entry from crypttab, finally initramfs and grub is called
              
              comment steps that are unnecessary in your rollback scenario 
    
EOH
    return 0
  fi
  umountBoot
  cryptdisks_stop boot_crypt
  mkfsAndCopy $fs $btDvc rollback
  removeKey
  updateInitNGrub
}
