#!/bin/bash

helptext(){
    cat << EOH
$0 [options] [arg] - create backup arg/@date_string for any mount btrfs fs
        
        options: -h/--help print this message
        
        arg - any btrfs mount point (defaults to /home/ )
        exit codes:
            0  - backup succeeded
            1  - no mount point
            -1 - no matching source device or parent volume found
            -2 - decryption/mount of destination device failed
			-3 - no snapshot created on given local subvol

EOH
}
mp_fl=/home/gab2/bin/backup.map
allUUIDs(){
	str=
	for i in $(cut -d' ' -f1 $mp_fl ); do
		[ -z "$str" ] && str=$i || str="$str\|$i"
	done
	echo $str
}
declare -a args=( $@ )
vol_str=${args[0]}

if [[ "$vol_str" == "-h" || "$vol_str" == "--help" ]]; then
	helptext && exit 0
fi

if [ -z "$backvol" ]; then
	tmp_fl=/tmp/.inxi-M.out
	[ ! -f $tmp_fl ] && inxi -M >> $tmp_fl
	if grep XPS $tmp_fl; then
    	backvol=2
	elif grep "\(VirtualBox\|QEMU\)" $tmp_fl; then
		backvol=3
	else
    	backvol=1
	fi
	export backvol=$backvol
	export PATH=/home/gab2/bin:$PATH
fi
echo "backup subvol suffix found: $backvol"


. mountLuksDev.sh >> /dev/null

[ -z "$vol_str" ] && vol_str=/home

len=${#vol_str}

[[ "${vol_str:$((len-1))}" != "/" ]] && vol_str="$vol_str/"

if [ ! -d $vol_str ]; then
    echo no such mount point $vol_str
    exit 1
fi

cd $vol_str
pwd
dt_str=$(date +%Y%m%d)
parent_vol=$(btrs list ./ | grep -v "@$dt_str" | cut -d' ' -f9 | grep "^@20\(2[4-9]\|[3-9][0-9]\)" | tail -1 )

if [[ "$?" != "0" || -z "$parent_vol" ]]; then
    echo "No suitable subvol found for parent in $vol_str"
    exit -1
fi

echo Found parent volume "$vol_str$parent_vol"

child_vol=$(btrs list ./ | cut -d' ' -f9 | grep "^@$dt_str" | tail -1 | sed "s/\/\?\(.\+\)/\/\1/g" | grep ".\+")

if [ -z "$child_vol" ]; then # no child subvol -> create new snapshot,
    child_vol=$(btrs snapshot -r $vol_str "@$dt_str" | grep -q "Create" && echo "@$dt_str" )
    [ -z "$child_vol" ] && echo snapshot creation failed - check dmesg/journal for more info && exit -3
	echo "and new child volume $vol_str$child_vol created"
else
    child_vol=$(echo $child_vol | sed "s/\/\(.\+\)/\1/g" )
    echo "and child volume found: $vol_str$child_vol"
fi

UUID=
sbvl=
dvc=$(blkid | grep LUKS | grep "\($(allUUIDs )\)" | sed "s/\(\/dev\/sd[a-z][1-9]\).\+/\1/g" )
echo $dvc used as backup
UUID=$(blkid -s UUID -o value $dvc )
echo having UUID $UUID
sbvl="$(grep $UUID $mp_fl | cut -d' ' -f2 )"
ssvl=@home
if echo $vol_str | grep -v home; then
    if echo $vol_str | grep var; then
        ssvl=@var
    elif echo $vol_str | grep opt; then
        ssvl=@opt
    else
        ssvl=@root
    fi
    # sbvl=$(echo sbvl | sed "s/home/$ssvl/g" )
fi
ssvl=${ssvl}$backvol
echo backup subvol found: $sbvl
if [ ! -z "$sbvl" ]; then 
    dvc=$(echo $dvc | sed "s/\/dev\///g" )
    if [ -z "$(mount | grep $dvc )" ]; then
        [ -z "$BACK_UP_REC_CALL" ] && mountLuksDev $dvc gab2 $sbvl/$ssvl || mountTemp gab2 /dev/mapper/${dvc}_crypt /dev/$dvc $sbvl/$ssvl rw
    fi
    if [ -z "$(mount | grep $dvc | grep $UUID )" ]; then
        echo luks mount failed for $dvc and subvol $sbvl
        exit -2
    fi
    echo backup subvol mounted
    dr=/media/gab2/$UUID/
    chl_vol="$vol_str$child_vol"
    prn_vol="$vol_str$parent_vol"
    fl=
	ext=0
    pr_chk=$(btrs list $dr | cut -d' ' -f9 | grep "^$parent_vol" )
    ch_chk=$(btrs list $dr | cut -d' ' -f9 | grep "^$child_vol" )
    if [[ -n "$pr_chk" && -z "$ch_chk" ]]; then
        echo "btr send -p $prn_vol $chl_vol | btr receive $dr"
        if btr send -p "$prn_vol" "$chl_vol" | btr receive $dr; then
			echo "Child vol: \"$chl_vol\" of parent vol: \"$prn_vol\" sent to '$dr'"
        else
			ext=-4            
			fl=fail
		fi
    elif [[ -n "$pr_chk" && -n "$ch_chk" ]]; then
        echo both volumes found - nothing to do
    fi
	sz=${#args[@]}
    if [[ "$sz" != "0" ]]; then
		if [ -z "$BACK_UP_REC_CALL" ]; then
			export BACK_UP_REC_CALL=1
		else
			fl=rec_call
		fi
        if [[ "$sz" > "1" ]]; then
            umountTemp $dr
			if ! $0 ${args[@]:1}; then
				ext=$?
				fl=fail_rec
			fi
		fi
    fi
    if [[ -z "$fl" ]]; then
		umountLuksDev $dvc gab2
	elif [[ "$fl" == "rec_call" ]]; then
        
        exit 0
	else
		echo "backup failed with flag '$fl' - check device $dvc for issues"
		exit $ext
	fi
fi
