#!/bin/bash

helptext(){
    cat << EOH
        $0 [options] [arg]
                            create backup arg/@date_string for
                            any mount btrfs fs

        files:
            /home/\$ADM_USER/*/backup.map   - two columns, maps backup UUID to common backup
                                              subvolume (required!)
            /home/\$ADM_USER/*/subvol.conf  - maps machine name to backup subvolume (tbd!)
        
        options: -h/--help print this message
        
        arg - any btrfs mount point (defaults to /home/ )
        exit codes:
            0  - backup succeeded
            $ERR_PAR - decryption/mount of destination device failed
            $ERR_MOU - no mount point
            $ERR_VOL - no matching source device or parent volume found
            $ERR_CHL - no snapshot created on given local subvol
            $ERR_SVL - no destination subvolume found
            $ERR_SND - sending incremental failed
            $ERR_BTH - neither parent nor child snapshot found
            $ERR_PRV - no parent snapshot found
            $ERR_CHV - no child snapshot found
            $ERR_MAP - no destination device mapping file
            $ERR_NOD - no destination backup device

EOH
}


. mountLuksDev.sh >> /dev/null

vol_str=
mp_fl=/home/$ky_user/bin/backup.map


dt_str= # date string - name of backup snapshot to create

parent_vol= # last shared snapshot (aka parent), should implement 'inner join' aka all destination snapshots and source snapshots
            # needed to perform incremental backups

child_vol=  # new/just created snapshot
UUID=       # destination device UUID
sbvl=       # 
ssvl=
dvc=
backvol=
dr=
ext=
fl=
frst=

ERR_PAR=1
ERR_MOU=2
ERR_VOL=3
ERR_CHL=4
ERR_SVL=5
ERR_SND=6
ERR_BTH=7
ERR_PRV=8
ERR_CHV=9
ERR_MAP=10
ERR_NOD=11

allUUIDs(){
	str=
	for i in $(cut -d' ' -f1 $mp_fl ); do
		[ -z "$str" ] && str=$i || str="$str\|$i"
	done
	echo $str
}

getBUVolId(){
    if [ -z "$backvol" ]; then
        sys_fl=$(inxi -M | grep product | sed "s=.\+product\: \(\(MacBookAir\|Standard\|XPS\|HP\)[^\:]\+\)\sv\:.\+=\1=g" )
        case "$sys_fl" in
        "Standard"|"VirtualBox")
		    backvol=4
            ;;
        'MacBookAir')
		    backvol=3
            ;;
	    'XPS')
        	backvol=2
            ;;
	    'HP Laptop 15-db0xxx')
        	backvol=1
            ;;
        *) # TODO should be exact check not generic, new generic should be error
            backvol=0
	    esac
	    export backvol=$backvol
#	    export PATH=/home/gab2/bin:$PATH
    fi
    echo "backup subvol suffix found: $backvol"
}

findVol(){
    if echo $vol_str | grep -v home; then
        if echo $vol_str | grep -q var; then
            ssvl=@var
        elif echo $vol_str | grep -q opt; then
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
        return $ERR_MOU
    fi
}
getParent(){
    lvl_id=$(listByPat $dr "\s$ssvl\$" | get2ndCol | tail -1 )
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
    [ ! -f $mp_fl ] && echo "no such backup mapping file $mp_fl - aborting" && return $ERR_MAP
    dvc=${dvc:-''}
    echo testing device $dvc
    [ -n "$dvc" ] && return 0
    for i in $(awk '{print $1}' $mp_fl ); do
        dv=$(blkid -o device -t UUID=$i )
        [ -n "$dv" ] && dvc=$dv && return 0
    done
    echo no backup destination device found - exiting
    return $ERR_NOD
}

initChild(){
    child_vol=$(getChild )

    if [ -z "$child_vol" ]; then # no child subvol -> create new snapshot,
        child_vol=$(btrs snapshot -r $vol_str "@$dt_str" | grep -q "Create" && echo "@$dt_str" )
        [ -z "$child_vol" ] && echo snapshot creation failed - check dmesg/journal for more info && return $ERR_CHL
	    echo "and new child volume $vol_str$child_vol created"
    else
        child_vol=$(echo $child_vol | sed "s/\/\(.\+\)/\1/g" )
        echo "and child volume found: $vol_str$child_vol"
    fi
}
sendSnap(){
    prn_vol=${prn_vol:-1}
    chl_vol=${chl_vol:-2}
    if [[ -z "$prn_vol" || -z "$chl_vol" ]]; then
        [[ -z "$prn_vol" && -z "$chl_vol" ]] && echo neither parent nor child subvolume found && return $ERR_BTH
        [[ -z "$prn_vol" ]] && echo no parent subvolume found && return $ERR_PRV
        echo no child subvolume found && return $ERR_CHV
    fi
    ch_chk=$(listByPat $dr "$ssvl/$child_vol\$" | get9thCol )
    if [ -z "$ch_chk" ]; then
        echo "btr send -p $prn_vol $chl_vol | btr receive $dr$ssvl"
        if btr send -p "$prn_vol" "$chl_vol" | btr receive $dr$ssvl; then
		    echo "Child vol: \"$chl_vol\" of parent vol: \"$prn_vol\" sent to '$dr$ssvl'"
        else
		    ext=$ERR_SND
		    fl=fail
	    fi
    elif [ -n "$ch_chk" ]; then
        echo both volumes found - nothing to do
    fi
}
umountDvc(){
    echo umounting backup destination and encrypting for $dvc triggered by $vol_str0...
    umountLuksDev ${dvc//'/dev/'/} gab2
    echo done
}
nextStep(){
    sz=$#
    echo $fl
    if [[ $sz -le 1 && -z "$BACK_UP_REC_CALL"  ]]; then
        umountDvc
        return 0
    fi    
    if [ -z "$BACK_UP_REC_CALL" ]; then
	    export BACK_UP_REC_CALL=1
        frst=$vol_str
        echo $frst is init vol
    fi
    if [[ $sz -gt 1 && $ext -eq 0 ]]; then
#            echo umountTemp $dr
        shift
	    main $@
		ext=$?
        if [ $ext -ne 0 ]; then
		    fl=fail_rec
            return $ext
        fi
    fi
    echo current vol: $vol_str0, init vol: $frst
    [[ "$vol_str0" == "$frst" || "$vol_str0/" == "$frst" ]] && umountDvc
    return 0
    
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
    local vol_str0=$1
    case "$vol_str" in 
    "-h" |"--help" )
        helptext && return 0
        ;;
    '')
        vol_str=/home
        ;;
    esac

    len=${#vol_str}

    if [ ! -d $vol_str ] || ! mount | grep btrfs | awk '{print $3}' | grep $vol_str; then
        echo no such mount point $vol_str
        return $ERR_VOL
    fi
    
    [[ "${vol_str:$((len-1))}" != "/" ]] && vol_str="$vol_str/"

    cd $vol_str
    pwd
    if ! findDevice ; then
        [ $? = $ERR_NOD ] && echo no device found - aborting && return $ERR_NOD
        return $ERR_MAP
    fi
    echo $dvc used as backup
    UUID=${UUID:-$(blkid -s UUID -o value $dvc )}
    echo having UUID $UUID
    sbvl=${sbvl:-"$(grep $UUID $mp_fl | get2ndCol )"}
    dt_str=${dt_str:-$(getTS )}
    ssvl=@home
    findVol 
    getBUVolId
    ssvl=${ssvl}$backvol
    echo backup subvol found: $sbvl
    if [ -z "$sbvl" ]; then 
        echo No suitable subvolume found
        return $ERR_SVL
    fi
    mountDvc || return $? 
    echo backup subvol mounted
    dr=/media/gab2/$UUID/
    getParent
    if [ -z "$parent_vol" ]; then
        echo "No suitable subvol found for parent in $vol_str and $dr"
        return $ERR_PAR
    fi
    echo Found parent volume "$vol_str$parent_vol"
    initChild || return $?
    
    prn_vol="$vol_str$parent_vol"
    chl_vol="$vol_str$child_vol"
#    fl=
    ext=${ext:-0}
    sendSnap || return $? # $prn_vol $chl_vol
    nextStep $@ || return $?
}
main $@
