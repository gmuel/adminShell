#!/bin/bash



helptxt(){
    cat << EOH
  $0 [options] BTRFS-MOUNT ZFS-DATASET

    Copies BTRFS snapshots under BTRFS-MOUNT (1) to ZFS-DATASET (2)
    Each subvolume of (1) gets its own dataset in (2) with same name and each
    snapshot will get rsync'd and a ZFS snapshot created for said dataset.
    Any '@' symbol are removed from datasets names
    E.g:
    BTRFS:
    -> subvol1  -> snap1
                -> snap2
                ...
                -> snapN
    ...
    ZFS:
    -> subvol1  -> @snap1
                -> @snap2
                ...
                -> @snapN
    ...

    Args:
          BTRFS-MOUNT   BTRFS mount point
          ZFS-DATASET   parent dataset for backup

    Options:
          -h/--help print this message    
EOH
}


_btr_src=${1}
_zp=${2}
_mnt=$(zpool get altroot -H -o value $(echo $_zp | cut -d/ -f1 ) )

if [ -z "$_btr_src" ] || [ -z "$_zp" ]; then
    exit 1
fi
btrfs sub list -o $_btr_src | awk '{print $9}' | while read _svl; do
    _zvl=${_svl//@/}
    if ! zfs list -H -o name $_zp/$_zvl 2>> /dev/null; then
        zfs create -o mountpoint=/$_zvl $_zp/$_zvl
    fi
#    if btrfs sub list -o $_btr_src/$_svl | awk '{print $9}' | sed "s|@||g" | grep "\S\+"; then
#        $0 $_btr_src/$_svl $_zp/$_zvl
#    fi
    btrfs sub list -o -s $_btr_src/$_svl | awk '{print $14}' | while read _snp; do
        if rsync -aprAHP $_btr_src/$_snp $_mnt/$_zvl; then
            _nm=$(basename $_snp | sed "s|@||g" )
            zfs snapshot $_zp/$_svl@$_nm
        fi
    done
done
