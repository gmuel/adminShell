#!/bin/bash

helptext(){
    cat << EOH
$0 [options] [arg] - create backup arg/@date_string for any mount btrfs fs
        
        options: -h/--help print this message
        
        arg - any btrfs mount point (defaults to /home/ )
        exit codes:
            0  - backup succeeded
            $ERR_PAR - decryption/mount of destination device failed
            $ERR_MOU - no mount point
            $ERR_VOL - no matching source device or parent volume found
			$ERR_CHL - no snapshot created on given local subvol
            $ERR_SVL - no 

EOH
}


. mountLuksDev.sh >> /dev/null

vol_str=
mp_fl=/home/gab2/bin/backup.map


dt_str=
parent_vol= # $(btrs list ./ | grep -v "@$dt_str" | grep "\s\+@20\(2[4-9]\|[3-9][0-9]\)" | tail -1 | cut -d' ' -f9 )
child_vol=
UUID=
sbvl=
dvc=
backvol=
dr=

ERR_PAR=1
ERR_MOU=2
ERR_VOL=3
ERR_CHL=4
ERR_SVL=5

allUUIDs(){
	str=
	for i in $(cut -d' ' -f1 $mp_fl ); do
		[ -z "$str" ] && str=$i || str="$str\|$i"
	done
	echo $str
}

getBUVolId(){
    if [ -z "$backvol" ]; then
	    tmp_fl=/tmp/.inxi-M.out
	    [ ! -f $tmp_fl ] && inxi -M >> $tmp_fl
        if grep "\(QEMU\|VirtualBox\)" $tmp_fl; then
		    backvol=4
        elif grep Apple $tmp_fl; then
		    backvol=3
	    elif grep XPS $tmp_fl; then
        	backvol=2
	    elif grep HP $tmp_fl; then
        	backvol=1
        else
            backvol=0
	    fi
	    export backvol=$backvol
	    export PATH=/home/gab2/bin:$PATH
    fi
    echo "backup subvol suffix found: $backvol"
}

findVol(){
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
}
mountDvc(){
    dvc0=$(echo $dvc | sed "s=/dev/==g" )
    if [ -z "$(mount | grep "\($dvc0\|luks-$UUID\)" )" ]; then
        if [ -z "$BACK_UP_REC_CALL" ] && [ ! -L /dev/mapper/luks-$UUID ]; then
            mountLuksDev $dvc0 gab2 $sbvl
        else
            echo mountTemp gab2 /dev/mapper/luks-$UUID $dvc $sbvl rw
        fi
    fi
    if [ -z "$(mount | grep "\($dvc0\|luks-$UUID\)" )" ]; then
        echo luks mount failed for $dvc and subvol $sbvl
        exit $ERR_MOU
    fi
}
getParent(){
    lvl_id=$(listByPat $dr "$ssvl\$" | get2ndCol )
    echo $lvl_id
    if [ -n "$lvl_id" ]; then
        vol=$(listByLevel $dr $lvl_id | get9thCol | tail -1 | sed "s=\(@[^\S/]*/\)\{0,\}==g" )
        echo $vol
        if listByPat $vol_str $vol | grep .; then
            parent_vol=$vol
        fi
    fi
}
getChild(){
    lvl_id=$(listByPat $vol_str "@$dt_str" | get2ndCol )
    if [ -n "$lvl_id" ]; then
        listByLevel $vol_str $lvl_id | get9thCol
    fi
}
getTS(){
    date +%Y%m%d_%H%M
}
findDevice(){
    dv=
    for i in $(awk '{print $1}' $mp_fl ); do
        dv=$(blkid -o device -t UUID=$i )
        [ -n "$dv" ] && echo $dv && break
    done
}

initChild(){
    child_vol=$(getChild )

    if [ -z "$child_vol" ]; then # no child subvol -> create new snapshot,
        child_vol=$(btrs snapshot -r $vol_str "@$dt_str" | grep -q "Create" && echo "@$dt_str" )
        [ -z "$child_vol" ] && echo snapshot creation failed - check dmesg/journal for more info && exit $ERR_CHL
	    echo "and new child volume $vol_str$child_vol created"
    else
        child_vol=$(echo $child_vol | sed "s/\/\(.\+\)/\1/g" )
        echo "and child volume found: $vol_str$child_vol"
    fi
}

#if inxi -M | grep Apple; then
#    backvol=3
#elif inxi -M | grep XPS; then
#    backvol=2
#else
#    backvol=1
#fi
#echo "backup subvol suffix found: $backvol"

main(){
    vol_str=$1
    
    case "$vol_str" in 
    "-h" |"--help" )
        helptext && exit 0
        ;;
    '')
        [ -z "$vol_str" ] && vol_str=/home
        ;;
    esac

    len=${#vol_str}

    if [ ! -d $vol_str ] || ! mount | grep btrfs | awk '{print $3}' | grep $vol_str; then
        echo no such mount point $vol_str
        exit $ERR_VOL
    fi
    
    [[ "${vol_str:$((len-1))}" != "/" ]] && vol_str="$vol_str/"

    cd $vol_str
    pwd
    dvc=${dvc:-$(findDevice )}
    echo $dvc used as backup
    UUID=${UUID:-$(blkid -s UUID -o value $dvc )}
    echo having UUID $UUID
    sbvl="$(grep $UUID $mp_fl | get2ndCol )"
    dt_str=$(getTS )
    ssvl=@home
    findVol 
    getBUVolId
    ssvl=${ssvl}$backvol
    echo backup subvol found: $sbvl
    if [ -z "$sbvl" ]; then 
        echo No suitable subvolume found
        return $ERR_SVL
    fi
    mountDvc
    echo backup subvol mounted
    dr=/media/gab2/$UUID/
    getParent
    if [ -z "$parent_vol" ]; then
        echo "No suitable subvol found for parent in $vol_str and $dr"
        exit $ERR_PAR
    fi
    echo Found parent volume "$vol_str$parent_vol"
    initChild
    
    chl_vol="$vol_str$child_vol"
    prn_vol="$vol_str$parent_vol"
    fl=
    ext=0
    ch_chk=$(listByPat $dr "$ssvl/$child_vol\$" | get9thCol )
    if [ -z "$ch_chk" ]; then
        echo "btr send -p $prn_vol $chl_vol | btr receive $dr$ssvl"
        if btr send -p "$prn_vol" "$chl_vol" | btr receive $dr$ssvl; then
		    echo "Child vol: \"$chl_vol\" of parent vol: \"$prn_vol\" sent to '$dr$ssvl'"
        else
		    ext=-4            
		    fl=fail
	    fi
    elif [ -n "$ch_chk" ]; then
        echo both volumes found - nothing to do
    fi
    sz=$#
    if [[ "$sz" != "0" ]]; then
	    if [ -z "$BACK_UP_REC_CALL" ]; then
		    export BACK_UP_REC_CALL=1
	    else
		    fl=rec_call
	    fi
        if [[ "$sz" > "1" ]]; then
            echo umountTemp $dr
            shift
		    if ! main $@; then
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
}
main $@
