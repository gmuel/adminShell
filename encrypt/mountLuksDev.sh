#!/bin/bash
helptxt(){
    echo
    case $1 in 
        "printKeyFile") echo " printKeyFile [OPTION] SRC_DVC - key file for device DVC"
                    ;;
        "mapUUID") echo " mapUUID [OPTION] UUID - maps UUID to key file"
                    ;;
        "listExternalLUKS") echo " listExternalLUKS [OPTION] - list external LUKS devices"
                    ;;
        "decrypt") echo " decrypt [OPTION] LUKS_DVC - decrypt LUKS device LUKS_DVC"
                    ;;
        "mountTemp") echo " mountTemp [OPTION] USER DECRYPT_DVC LUKS_DVC [SUB_VOL] [READ_FLAG] - mount LUKS_DVC/SUB_VOL"
                    echo "            to /media/USER/UUID_OF_LUKS_DVC/"
                    echo "          Note - only valid for btrfs filesystems and defaults to read-only mount(!)"
                    ;;
        "mountLuksDev") echo " mountLuksDev [OPTION] SRC_DVC USER [SUB_VOL] - decrypt and mount SRC_DVC/SUB_VOL"
                    echo "            to /media/USER/UUID_OF_SRC_DVC/"
                    echo "          Note - only valid for LUKS encrypted btrfs filesystems and read-only mount(!)"
                    ;;
        "getUUID") echo " getUUID [OPTION] DVC - UUID for DVC"
                    ;;
        "encrypt") echo " encrypt [OPTION] SRC_DVC - encrypt SRC_DVC"
                    ;;
        "umountTemp") echo " umountTemp [OPTION] DECRYPT_DVC - unmount DECRYPT_DVC"
                    ;;
        "umountLuksDev") echo " umountLuksDev [OPTION]  SRC_DVC USER  - unmount SRC_DVC"
                    echo "            and re-encrypt SRC_DVC"
                    ;;
    esac
    echo "      ARGS:"
    case "$1" in
        "mountTemp"|"umountTemp") 
            echo "          DECRYPT_DVC     /full/path/to/decrypted/device"
            echo "                  e.g. /dev/mapper/sda1_crypt, .."
    esac
    case "$1" in
        "printKeyFile"|"mountLuksDev" | "encrypt"|"umountLuksDev") 
            echo "          SRC_DVC     source block device, e.g. sda1, sdc2, .."
            case "$1" in
                "mountTemp"|"mountLuksDev" | "umountLuksDev") echo "          USER           valid system user"
            esac
            ;;
        "decrypt"|"mountTemp")
            echo "          LUKS_DVC    /full/path/to/encrypted/device, e.g. /dev/sda1, .."
            ;;
        "getUUID")
            echo "          DVC     /full/path/to/device"
            ;;
        
    esac
    case "$1" in
        "mountTemp"|"mountLuksDev") 
	    echo "          READ_FLAG	   permitted read options: ro, rw"
            echo "          SUB_VOL        valid btrfs subvoume, e.g. @home"
    esac
    echo "      OPTION:"
    echo "          -h/--help       print this message"
    echo "          -v/--version    print version"
}
printVersion(){ echo "$1 - version 1.0"; }
printHelp(){
    [[ "$1" == "-h" || "$1" ==  "--help" ]] && helptxt $2 && return 0
    [[ "$1" == "-v" || "$1" ==  "--version" ]] && printVersion $2 && return 0
    return 1  
}
devFile=/home/gab2/bin/devMap.txt
declare -a uuids=( $(cut -d' ' -f1 $devFile ) )
echo ${uuids[@]}
printKeyFile(){
    printHelp "$1" "printKeyFile" && return 0
    for i in ${uuids[@]}; do
        blkid | grep $i | grep -q $(echo $1 | sed "s/[0-9]\$//g" ) && mapUUID $i && break
    done
}
mapUUID(){
    printHelp "$1" "mapUUID" && return 0
    grep $1 $devFile | cut -d' ' -f2
}
listExternalLUKS(){
    printHelp "$1" "listExternalLUKS" && return 0
    for i in $(ls /dev/sd* 2>> /dev/null ); do
        blkid -s TYPE -o value $i | grep -i -q luks && echo $i
    done
}
decrypt(){
    printHelp "$1" "decrypt" && return 0
    ky_fl=$(printKeyFile $1 )
    [ -z "$ky_fl" ] && return -1
    cryptsetup luksOpen $2 ${1}_crypt --key-file /root/.keys/$ky_fl    
}
declare -a mounted_dirs=( ${mounted_dirs[@]} )
mountTemp(){
    printHelp "$1" "mountTemp" && return 0
    uuid=$(getUUID $3 )
    sz=${#mounted_dirs[@]}
    mounted_dirs[$sz]="/media/$1/$uuid"
    if mkdir -p ${mounted_dirs[$sz]} ; then
        chown $1 ${mounted_dirs[$sz]}
	    optFl=
	    if [ -z "$5" ]; then
	       optFl=ro
	    else
	        optFl=rw
	    fi
        if [ ! -z "$4" ]; then
            echo mount -t btrfs -o $optFl,subvol=$4 $2 ${mounted_dirs[$sz]}            
            mount -t btrfs -o $optFl,subvol=$4 $2 ${mounted_dirs[$sz]}
        else
            echo mount -t btrfs -o ro $2 ${mounted_dirs[$sz]}
            mount -t btrfs -o ro $2 ${mounted_dirs[$sz]}
        fi
    fi
}
getBlkChars(){
	blkid -s $1 -o value $2 | grep $3 $4 $5
}
mountLuksDev(){
    printHelp "$1" "mountLuksDev" && return 0
    dr0=/dev/$1
    dr1=/dev/mapper/${1}_crypt 
    cmd="getBlkChars TYPE $dr0 -q -i luks"
    echo $cmd   
    if $cmd ; then
        cde=0
	    cmd="getBlkChars UUID $dr1 -q ."
	    echo $cmd
        if ! $cmd ; then
            cmd="decrypt $1 $dr0"
	        $cmd 
            cde=$?
        fi
	    openOpt=
	    if [ -z "$4" ]; then
 	        openOpt=rw
	    else
	        openOpt=$4 
	    fi
        if [[ $cde == 0 ]]; then
	        cmd="mountTemp $2 $dr1 $dr0 $3 $openOpt"
	        echo $cmd
	        $cmd	
	    fi
    fi
}
printFirstSubvol(){
    k=$2
    [ -z "$k" ] && k=3 || k=$(($k+3))
    for i in ${uuids[@]}; do
        pattn="$(blkid | grep $i | grep $(echo $1 | sed "s/[0-9]\$//g" ) | sed "s/.\+UUID=\"\([0-9a-f]\+\(\-[0-9a-f]\+\)\+\)\".\+/\1/g" )"
        [ ! -z "$pattn" ] && grep "$pattn" $devFile | cut -d' ' -f $k && break
    done
}
getUUID(){
    printHelp "$1" "getUUID" && return 0
    blkid -s UUID -o value $1
}
encrypt(){
    printHelp "$1" "encrypt" && return 0
    cryptsetup luksClose ${1}_crypt
}
umountTemp(){
    printHelp "$1" "umountTemp" && return 0
    umount $1 && rmdir $1 && \
        mounted_dirs=( $(for i in ${mounted_dirs[@]}; do [[ "$i" != "$1" ]] && echo $i; done ) )
}
umountLuksDev(){
    printHelp "$1" "umountLuksDev" && return 0
    uuid=$(getUUID /dev/$1 )
    dr0=/media/$2/$uuid
    [[ -d $dr0 && -n "$(mount | grep $dr0 )" ]] && umountTemp $dr0 && encrypt $1
}
btr(){
    btrfs $@
}
btrs(){
    btr subvolume $@
}
printDvc(){
    ls /dev/sd*$1 | sed "s/\/dev\/\(sd.$1\)/\1/g"
}
createSnap(){
    btrs snapshot -r $1 "@$(date +%Y%m%d)"
}
sendSnap(){ 
    [ ! -z "$3" ] && btr send -p $1 $2 | btr receive $3 || btr send $1 | btr receive $2
}
alias listSnaps="btrs list"
getSubvol(){
	case "$1" in
	4c4) echo "@backup/@home2";;
	25) echo "@home2";;
	*)  echo "@old";;
	esac
}
mountLuks(){
	dvc=$(printDvc $1 )
	vol="$3"
	[ -z "$vol" ] && vol=$(blkid -s UUID -o value /dev/$dvc | sed "s/^\([a-zA-Z09]\{2\}\).\+/\1/g" ) && vol=$(getSubvol $vol )
	mountLuksDev $dvc $2 $vol
}
