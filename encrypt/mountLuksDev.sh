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
printKeyFile(){
    printHelp "$1" "printKeyFile" && return 0
    declare -a uuids=( 75525cc0-54d3-4cbd-aca7-1620e802ebd3 75c6f82d-186f-44b6-8c1b-2dff7538c232 e46e8fc0-edac-4cf2-b477-42114cda29fb e3567221-2b55-46b0-8af1-915b4b1e2ae7 2570b821-53d2-4aba-a5c6-e9d0ccb43229 4c4656d9-9093-4bbc-9962-baf3c8cb8fe4 e6ed36e4-0deb-4957-bf94-c3b70c5017af )
    for i in ${uuids[@]}; do
        blkid | grep $i | grep -q $(echo $1 | sed "s/[0-9]\$//g" ) && mapUUID $i
    done
}
mapUUID(){
    printHelp "$1" "mapUUID" && return 0
    case $1 in
    75525cc0-54d3-4cbd-aca7-1620e802ebd3) echo .sea_key
        ;;
    75c6f82d-186f-44b6-8c1b-2dff7538c232) echo .san1_key
        ;;
    e46e8fc0-edac-4cf2-b477-42114cda29fb) echo .sam1_key
        ;;
    e3567221-2b55-46b0-8af1-915b4b1e2ae7) echo .san2_key
        ;;
    2570b821-53d2-4aba-a5c6-e9d0ccb43229) echo .san3_key
        ;;
    4c4656d9-9093-4bbc-9962-baf3c8cb8fe4) echo .wd_key
    	;;
    e6ed36e4-0deb-4957-bf94-c3b70c5017af) echo .sam4t_key
	;;
    esac
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
mountTemp(){
    printHelp "$1" "mountTemp" && return 0
    uuid=$(getUUID $3 )
    dr2=/media/$1/$uuid
    if mkdir -p $dr2 ; then
        chown $1 $dr2
	optFl=
	if [ -z "$5" ]; then
	   optFl=ro
	else
	    optFl=rw
	fi
        [ ! -z "$4" ] && mount -t btrfs -o $optFl,subvol=$4 $2 $dr2 || mount -t btrfs -o ro $2 $dr2
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
    umount $1 && rmdir $1
}
umountLuksDev(){
    printHelp "$1" "umountLuksDev" && return 0
    uuid=$(getUUID /dev/$1 )
    dr0=/media/$2/$uuid
    [[ -d $dr0 && -n "$(mount | grep $dr0 )" ]] && umountTemp $dr0 && encrypt $1
}
alias btr=btrfs
alias btrs="btr subvolume"

