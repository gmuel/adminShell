#!/bin/bash
vol_str=$1
if [[ "$vol_str" == "-h" || "$vol_str" == "--help" ]]; then
    cat << EOH
$0 [options] [arg] - create backup arg/@date_string for any mount btrfs fs
        
        options: -h/--help print this message
        
        arg - any btrfs mount point (defaults to /home/ )
        exit codes:
            0  - backup succeeded
            1  - no mount point
            -1 - no matching source device or parent volume found
            -2 - decryption/mount of destination device failed

EOH
    exit 0
fi
source /home/gab2/bin/mountLuksDev.sh >> /dev/null
[ -z "$vol_str" ] && vol_str=/home
len=${#vol_str}
[[ "${vol_str:$((len-1))}" != "/" ]] && vol_str="$vol_str/"
if [ ! -d $vol_str ]; then
    echo no such mount point $vol_str
    exit 1
fi
cd $vol_str
dt_str=$(date +%Y%m%d)
parent_vol=$(btrs list ./ | grep -v "@$dt_str" | grep "@20\(2[4-9]\|[3-9][0-9]\)" | tail -1 | cut -d' ' -f9 )
if [[ "$?" != "0" || -z "$parent_vol" ]]; then
    echo "No suitable subvol found for parent in $vol_str"
    exit -1
fi
echo Found parent volume "$vol_str$parent_vol"
child_vol=$(btrs list ./ | grep "@$dt_str" | tail -1 | cut -d' ' -f9 | sed "s/\/\?\(.\+\)/\/\1/g" | grep ".\+")
if [ -z "$child_vol" ]; then
     child_vol=$(btrs snapshot -r $vol_str "@$dt_str" | grep -q "Create" && echo "@$dt_str" )
    echo "and new child volume $vol_str$child_vol created"
else
    child_vol=$(echo $child_vol | sed "s/\/\(.\+\)/\1/g" )
    echo "and child volume found: $vol_str$child_vol"
fi
backvol=
if inxi -M | grep XPS; then
    backvol=2
else
    backvol=1
fi
echo "backup subvol suffix found: $backvol"
UUID=
sbvl=
dvc=$(blkid | grep LUKS | grep "\(dac895e7-151b-4894-98b1-5d7165ff8c76\|62bc1b28-ab06-4e28-8167-2fe0e3c9499d\)" | sed "s/\(\/dev\/sd[a-z][1-9]\).\+/\1/g" )
echo $dvc used as backup
UUID=$(blkid -s UUID -o value $dvc )
echo having UUID $UUID
sbvl="$(grep $UUID /home/gab2/bin/backup.map | cut -d' ' -f2 )$backvol"
if echo $vol_str | grep -v home; then
    ssvl=
    if echo $vol_str | grep var; then
        ssvl=var
    elif echo $vol_str | grep opt; then
        ssvl=opt
    else
        ssvl=root
    fi
    sbvol=$(echo sbvl | sed "s/home/$ssvl/g" )
fi
echo backup subvol found: $sbvl
if [ ! -z "$sbvl" ]; then 
    dvc=$(echo $dvc | sed "s/\/dev\///g" )
    if [ -z "$(mount | grep $dvc )" ]; then
        mountLuksDev $dvc gab2 $sbvl
    fi
    if [ -z "$(mount | grep $dvc | grep $UUID )" ]; then
        echo luks mount failed for $dvc and subvol $sbvl
        exit -2
    fi
    echo backup subvol mounted
    dr=/media/gab2/$UUID
    chl_vol="$vol_str$child_vol"
    prn_vol="$vol_str$parent_vol"
    fl=
    pr_chk=$(btrs list $dr | cut -d' ' -f9 | grep "^$parent_vol" )
    ch_chk=$(btrs list $dr | cut -d' ' -f9 | grep "^$child_vol" )
    if [[ -n "$pr_chk" && -z "$ch_chk" ]]; then
        echo "btr send -p $prn_vol $chl_vol | btr receive $dr"
        btr send -p "$prn_vol" "$chl_vol" | btr receive $dr && \
            echo "Child vol: \"$chl_vol\" of parent vol: \"$prn_vol\" sent to '$dr'" || \
                fl=0
    elif [[ -n "$pr_chk" && -n "$ch_chk" ]]; then
        echo both volumes found - nothing to do
    fi
    declare -a args=( $@ )
    if [[ ${#args[@]} != 0 ]]; then
        $0 ${args[@:1:]}
    fi
    [ -z "$fl" ] && umountLuksDev $dvc gab2 || echo "backup failed - check device $dvc for issues"
fi
