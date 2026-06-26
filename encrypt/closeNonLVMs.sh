#!/bin/bash
helptxt(){
	cat << EOH
 $0 [options]
 Close/encrypt all luks devices matching luks-UUID pattern
 found in /dev/mapper
 Only if filesystem isn't an LVM nor is device mapped block in use (mounted)
 this will succeed. All other DMBs are ignored.

   Options: -h/--help print this message

EOH
}
case "$1" in
	'-h'|'--help') helptxt; exit 0;
		;;
esac

ls /dev/mapper/luks-* | while read _lx; do
	blkid -s TYPE -o value $_lx | grep -v -i lvm && mount | grep -v -q $_lx && cryptdisks_stop $(basename $_lx )
done
