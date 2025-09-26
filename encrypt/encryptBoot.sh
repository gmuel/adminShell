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
                    NOTE that 'inxi' command is required for this script to work, install before usage(!)
      
EOF
  [ -z "$1" ] && return 0 || return $1
}
[[ "$1" == "-h" || "$1" == "--help" ]] && helptxt 0
[ -n "$1" ] && btDvc=$1 || btDvc=$(mount | grep '/boot ' | cut -d' ' -f1 )
# kyfl=$2
[ -n "$2" ] && fs=$2 || fs=$(grep '/boot ' /etc/fstab | sed "s/\s\+/ /g" | cut -d' ' -f3 )
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
  if [[ "$fs" == "xfs" ]]; then
    mkfs.$fs $dvc
  else
    mkfs.$fs -m0 $dvc
  fi
  refreshFSTab $3
  mountBoot
  tar -C /boot --acls --xattrs -xf /tmp/boot.tar
}
updateInitNGrub(){
  mount -a
  if inxi -S | grep -i "\(linux mint\|ubuntu\|debian\)"; then  
    update-initramfs -u -k all
    update-grub
    grub-install
  elif inxi -S | grep -i "\(fedora\|centos\)"; then
    grep "^GRUB_ENABLE_CRYPTODISK=y" /etc/default/grub || echo GRUB_ENABLE_CRYPTODISK=y | tee -a /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    cdf=/etc/dracut.conf.d/cryptodisk.conf
    grep "/etc/cryptsetup-keys.d" $cdf || echo "install_items+=\" /etc/cryptsetup-keys.d/* \"" | tee -a $cdf
    dracut -vf --regenerate-all -p
#    uuid1=$(blkid -s UUID -o value /dev/mapper/boot_crypt )
#    uuid2=${uuid1//'-'/''}
#    sed "s/\(search \-\-no\-floppy \-\-fs\-uuid \-\-set=dev \)\($uuid\)/cryptomount -u $uuid2\n\1\-\-hint='cryptouuid=/$uuid2' \2" /boot/efi/EFI/fedora/grub.cfg
#    dnf reinstall shim-\* grub2-efi-\* grub2-common -y
  else
    inxi -S 
    echo system not supported - update initramfs and grub manually
    return -1
  fi

}
createKeyFile(){
  if inxi -S | grep -i "\(fedora\|centos\)"; then
    kyfl=/etc/cryptsetup-keys.d/luks-${uuid}.key
  elif inxi -S | grep -i "\(linux mint\|debian\|ubuntu\)"; then
    kyfl=/root/.keys/.${uuid}.key
  fi
  runCmd dd if=/dev/urandom of=$kyfl bs=512 count=8
}
includeKey(){
  sed -i.1 "s/\(UUID=$1\) none \(luks\(,discard\)\?\)/\1 ${kyfl//'/'/'\/'} \2/g" /etc/crypttab
}
uuid=
trgt=
decryptBoot(){
  if inxi -S | grep -i "\(fedora\|centos\)"; then
    trgt=luks-$uuid
  elif inxi -S | grep -i "\(linux mint\|debian\|ubuntu\)"; then
    trgt=boot_crypt
  fi
  runCmd cryptsetup luksOpen $btDvc $trgt --key-file $kyfl && \
    runCmd mkfsAndCopy $fs /dev/mapper/$trgt
}
createLuks1Boot(){
  #echo   mount -o remount,ro /boot
  # mount -o remount,ro /boot
  runCmd mount -o remount,ro /boot && \
    runCmd "mount | grep /boot/efi && umount /boot/efi" && \
    runCmd install -m0600 /dev/null /tmp/boot.tar && \
    runCmd tar -C /boot --acls --xattrs --one-file-system -cf /tmp/boot.tar . && \
    runCmd umountBoot && \
    runCmd wipeBoot # && \
    runCmd cryptsetup luksFormat --type luks1 $btDvc && \
    runCmd uuid=$(blkid -o value -s UUID $btDvc) && \
    runCmd createKeyFile && \
    runCmd chmod 0600 $kyfl && \
    runCmd cryptsetup luksAddKey $btDvc $kyfl && \
    runCmd addKey && \
    runCmd decryptBoot && \
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
    grep ^$trgt /etc/crypttab && sed -i "s/^\($trgt UUID=[a-f0-9\-]\+.\+\)/\# \1 - archived on '$(date +%Y%m%d )'/g" /etc/crypttab
}
addKey(){
    removeKey
    addSlot=
    if inxi -S | grep -i "\(linux mint\|debian\|ubuntu\)"; then
      addSlot=,key-slot=1
    fi

    echo $trgt UUID=$uuid $kyfl luks,discard$addSlot | tee -a /etc/crypttab
}

refreshFSTab(){
    uuid1=
    [[ "$1" == "rollback" ]] && uuid1=$(blkid -s UUID -o value $btDvc ) || uuid1=$(blkid -s UUID -o value /dev/mapper/$trgt )
    sed -i "s/\(${btDvc//'/'/'\/'}\|UUID=$uuid\+\)\( \/boot .\+\)/UUID=$uuid1\2/g" /etc/fstab
    systemctl daemon-reload
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
  cryptsetup luksClose $trgt
  mkfsAndCopy $fs $btDvc rollback
  removeKey
  updateInitNGrub
}

wipeBoot(){
    rtd=$(echo $btDvc | sed "s/[0-9]\+/\$//g" )
    did=$(echo $btDvc | sed "s/.\+\([0-9]\$\)/\1/g")
    dsz=$(parted -s --list $rtd | grep "^ $did" | sed "s/\s\{2,\}/ /" | cut -d' ' -f5  )
    fct=1
    szflg=$(echo $dsz | sed "s/[0-9]\+//g" )
    case "$szflg" in
    'MB')
       fct=250 # = 1 MB divided by 4KB blocks
       ;;
     'M')
        fct=256
        ;;
     'GB')
        fct=250000
        ;;
     'G')
        fct=$((256*1024))
        ;;
      *)
        return 1
        ;;
     esac
    dsz=${dsz//"$szflg"/}
    runCmd dd if=/dev/urandom of=\$btDvc bs=4k count=$(($dsz*$fct)) seek=1 status=progress
}
