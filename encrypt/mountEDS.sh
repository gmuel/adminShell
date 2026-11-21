#!/bin/sh

if [ -z "$1" ] || ! zfs list -Ho name $1 >> /dev/null 2>&1 || [ "$(zfs get encryption -Ho value $1 )" = "-" ]; then
    exit 0
fi

_opt=
_mst=$(mount | awk "{if(\$1 == \"$1\"){print \$3}}" )

[ -n "$_mst" ] && exit 0

case "$(zfs get mountpoint -Ho value $1 )" in

    legacy)
        _mpt=$(awk "{if(\$1 == \"$1\"){print \$2}}" /etc/fstab )
        if [ -n "$_mpt" ]; then
            [ "$(zfs get keystatus -Ho value $1 )" != "available" ] && zfs load-key $1
            mount -t zfs $1 $_mpt
        fi
        ;;
    none)
        ;;
    *)
        [ "$(zfs get keystatus -Ho value $1 )" != "available" ] && _opt=-l
        zfs mount $_opt $1
        ;;
esac
exit 0
