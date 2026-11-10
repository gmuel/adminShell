#!/bin/bash
set -x

getBtrfsMnts(){
    mount | awk "{if(\$5 == \"btrfs\" && \$3 == \"$1\"){print \$${2:-1}}}" | grep -v "/\(mnt\|media\)"
}
baseSys(){
    for i in /{dev{,/{pts,shm}},proc,run,sys{,/firmware/efi/efivars}}; do
        echo $i
    done
}
getBtrfsFlgs(){
    getBtrfsMnts $1 6 | sed "s|.\+subvol=/\?\(@[^)]*\).\+|\1|g"
}
delRec(){
    for _svl in $(btrfs sub list -o $1 | awk '{print $9}' ); do
        delRec $1/$(basename $_svl )
    done
    btrfs sub delete $1
}
efiMounted(){
    mount | awk '{if($3 == "/boot/efi"){print $0}}' | grep -q "\S\+"
}
rmEFI(){
    _tmp=/mnt/$1/@/etc/machine-id
    if [ -f $_tmp ]; then
        efiMounted || mount /boot/efi
        if [ -d /boot/efi/EFI/Linux/ ]; then
            _efi=$(find /boot/efi/EFI/Linux/ -type f -name "linux-*-$(cat $_tmp ).efi" )
            [ -n "$_efi" ] && rm -vf $_efi
        fi
    fi
}
delPrev(){
    _svl=$(btrfs sub list -o $2 | awk '{print $9}' | grep "20\(2[6-9]\|[3-9][0-9]\)\-\(0[1-9]\|1[0-2]\)\-\(0[1-9]\|[12][0-9]\|3[01]\)" | grep -v "$1" )
    [ -z "$_svl" ] && return 0
    rmEFI $_svl
    delRec $2/$_svl
}
createSVolSnap(){
    if [ ! -d $1 ]; then
        delPrev $4 ${1//$4/}
        btrfs sub create $1
    fi
    [ ! -d $3 ] && btrfs sub snapshot $2 $3
}
mountHome(){
    [ -n "$_hm" ] && mount -t btrfs $_hm $1 && _hfl=0
}
_rt=$(getBtrfsMnts / )
_hm=$(getBtrfsMnts /home )
_hfl=
[ -z "$_rt" ] && exit 0
[ "$_rt" = "$_hm" ] && _hm=

mount -t btrfs $_rt /mnt

for i in $(mount | awk '{if($5 == "btrfs"){print $3}}' | grep -v "/m\(nt\|edia\)" ); do
    if [ -z "$_snp" ]; then
        _snp=$(btrfs sub list -o -s $i | awk '{print $14}' | tail -1 );
        _snp=$(basename $_snp )
    else
        _snp0=$(btrfs sub list -o -s $i | awk '{print $14}' | tail -1 );
        _snp0=$(basename $_snp0 )
        if [ "$_snp" != "$_snp0" ]; then
            delPrev $_snp $i
            exit 0
        fi
    fi
    _src=$(getBtrfsMnts $i )
    case "$_src" in
        "$_rt" )
            createSVolSnap /mnt/$_snp $i/$_snp /mnt/$_snp/$(getBtrfsFlgs $i ) $_snp || exit 0
            ;;
        "$_hm" )
            [ -z "$_hfl" ] && mountHome /mnt/@/mnt
            createSVolSnap /mnt/@/mnt/$_snp $i/$_snp /mnt/@/mnt/$_snp/$(getBtrfsFlgs $i ) $_snp || exit 0
            ;;
    esac
done

umount -R -l /mnt

mount -t btrfs -o rw,subvol=$_snp/$(getBtrfsFlgs / ) $_rt /mnt
_usr=$(getBtrfsFlgs /usr )
if [ -n "$_usr" ]; then
    mount -t btrfs -o rw,subvol=$_snp/$_usr $(getBtrfsMnts /usr ) /mnt/usr
fi

if ! grep $_snp /mnt/etc/fstab; then
    sed -i "s|\(subvol=\)|\1$_snp/|g" /mnt/etc/fstab
    systemctl daemon-reload
fi

efiMounted && umount /boot/efi
for i in $(baseSys ); do
    mount --rbind {,/mnt}$i
done
chroot /mnt mount -a
_kver=$(uname -r )
[ ! -d /mnt/lib/modules/$_kver ] && _kver=$(ls /mnt/lib/modules | tail -1 )

if [ -n "$(which dracut )" ]; then
    if ! grep $_snp /mnt/etc/dracut.conf.d/90-tpm2.conf; then
        sed -i "s|\(subvol=/\)|\1$_snp/|g" /mnt/etc/dracut.conf.d/90-tpm2.conf
        uuidgen | sed 's|-||g' > /mnt/etc/machine-id
    fi
    chroot /mnt /etc/kernel/postinst.d/zzz-dracut-regenerate-all $_kver
else
    _cfg=/etc/grub.d/40_custom
    if [ ! -f ${_cfg}.1 ]; then
	    cp ${_cfg}{,.1} # we keep a copy for future update-grub calls
    else
	    # in case of a new update-grub...
	    rm $_cfg
	    cp ${_cfg}{.1,}
        update-grub # clear any residual boot env entries
    fi
    awk -v RS=} "\$0 ~ /menuentry[^{]+$_kver[^{]+{/{print \$0\"}\"}" /boot/grub/grub.cfg | grep -v submenu | sed "s|\(subvol=/\?\)\([^\s]\+\)|\1$_snp/\2|g" >> /etc/grub.d/40_custom
    update-grub
fi
for i in $(baseSys | sort -r ); do
    umount /mnt$i
done

umount -R -l /mnt
