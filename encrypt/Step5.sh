#!/bin/bash

[ -z "$1" ] && echo Disk device missing - aborting && exit 1
rtd=$1

efi=${rtd}
dvc=${rtd}

if echo $rtd | grep nvme ; then
    efi=${efi}p
    dvc=${dvc}p
fi
efi=${efi}1
dvc=${dvc}2

uuid=$(blkid -s UUID -o value $dvc )
lxid=luks-$uuid
dmd=
if [ -L /dev/mapper/main_vol-root ]; then
    dmd=/dev/mapper/main_vol-root
else
    dmd=/dev/mapper/$lxid
fi

mount -a
#apt-cdrom add /dev/sr0
apt update

apt install -y cryptsetup efibootmgr binutils systemd-boot systemd-boot-efi gawk zstd # systemd-zram-generator


#fl=/etc/systemd/zram-generator.conf
#if [ ! -f $fl ] || ! grep zram-size $fl ; then
#    cat << EOI >> $fl
#zram-size = ram / 3
#compression-algorithm = zstd
#swap-priority = 100
#EOI
#fi

#cat $fl

#fl=/etc/sysctl.d/99-vm-zram-parameters.conf
#if [ ! -f $fl ] || ! grep '# /etc' $fl ; then
#    cat << EOI >> $fl
# /etc/sysctl.d/99-vm-zram-parameters.conf
#vm.swappiness = 180
#vm.watermark_boost_factor = 0
#vm.watermark_scale_factor = 125
#vm.page-cluster = 0
#EOI
#fi

#cat $fl

# RESUME=none" | tee -a /etc/initramfs-tools/conf.d/resume
fl=/etc/crypttab
if [ ! -f $fl ] || ! grep $lxid $fl ; then
    echo "$lxid UUID=$uuid none luks" | tee -a $fl
    uuid1=$(blkid -s UUID -o value $dmd )
    sed -i.bak "s/${dmd//'/'/'\/'}/UUID=$uuid1/" /etc/fstab
fi

cat $fl

locale-gen --purge --no-archive

mkdir -p /boot/efi/EFI/Boot


fl=/boot/efi/loader/loader.conf
if [ ! -f $fl ] || ! grep timeout $fl ; then
    [ -f $fl ] && sed -i.bak "s/^\(default\)/#\1/" $fl
    cat << EOI >> $fl
timeout            10
console-mode       max
editor             no
random-seed-mode   off
auto-entries       no
auto-firmware      no
EOI
fi

cat $fl

efibootmgr -c -d ${rtd} -p 1 -D -L "Linux Boot Manager" -l "\EFI\systemd\systemd-bootx64.efi"

apt update -y

apt remove -y --purge initramfs-tools

apt remove -y --purge initramfs-tools-core

apt install -y dracut


# if [ -n "$2" ]; then
    apt install -y tpm2-tools

    fl=/etc/dracut.conf.d/90-tpm2.conf
    if [ ! -f $fl ] || ! grep uefi $fl ; then
        cat << EOI >> $fl
uefi="yes"
kernel_cmdline="root=$dmd ro rootflags=subvol=/@ quiet splash"
add_dracutmodules+=" tpm2-tss "
use_fstab="yes"
install_items+=" /etc/crypttab "
compress="zstd"
EOI
    fi

cat $fl
# fi

fl=/etc/kernel/postinst.d/zzz-dracut-regenerate-all
if [ ! -f $fl ] || ! grep '#!/bin' $fl ; then
    cat << EOI >> $fl
#!/bin/sh
echo "RUNNING zzz-dracut-regenerate-all script --- START"
echo "Now regenerating all UKI files..."
sleep 3
dracut --force --regenerate-all -pv
echo "Regenerating all UKI files... Done"
sleep 3
echo "Now deleting all kernel systemd-boot related files..."
rm -rf /boot/efi/linuxmint/*
rm -rf /boot/efi/loader/entries/*
echo "Deleting all kernel systemd-boot related boot files... Done"
if [ -d /boot/efikeys ]; then
    echo "Now verifing signatures for all systemd-boot UKI files..."
    directory="/boot/efi/EFI/Linux"
    if [ -d "$directory" ]; then
        for file in "$directory"/*; do
            if [ -f "$file" ]; then
                echo "Now verifing signature for $file efi file..."
                sbverify --cert /boot/efikeys/db.crt $file
            fi
        done
    fi
    echo "Verifing signatures for all systemd-boot UKI files... Done"
fi
echo "RUNNING zzz-dracut-regenerate-all script --- END"
sleep 3
EOI
fi

cat $fl

chmod u+x /etc/kernel/postinst.d/zzz-dracut-regenerate-all

apt install -y plymouth plymouth-themes plymouth-label firefox

/etc/kernel/postinst.d/zzz-dracut-regenerate-all


