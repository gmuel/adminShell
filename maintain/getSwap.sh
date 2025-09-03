lvSwp=
dmSwp=
getEcrDev(){
    dmSwp=$(echo $1 | sed "s/\/dev\/mapper\///g" )
    if [ -n "$dmSwp" ]; then
        uuidE=$(grep $dmSwp /etc/crypttab | cut -d' ' -f2 | sed "s/UUID=//g" )
        if [ -n "$uuidE" ]; then
            blkid -o device -t UUID=$uuidE
        fi
    fi
}
composeLinkPath(){
    sz=${#1}
    for ((i=1;i<sz;i++)); do
        im=$(($i-1))
        if [[ "${1:$im:1}" == "-" ]]; then
            dr=/dev/${1:0:$im}/${1:$i:}
            [ -L $dr ] && echo $dr && break;
        fi
    done
}
getSwapDev(){
    
    swp=$(blkid -o device -t TYPE=swap | head -1 )
    [ -z "$swp" ] && echo ERROR: no swap device found - aborting... && exit 1
    uuidSwp=$(blkid -s UUID -o value -t TYPE=swap | head -1 )
    [ -z "$uuidSwp" ] && echo ERROR: no UUID found for swap device $swp && exit 2
    
    
    if ! echo $swp | grep -q mapper; then
        echo $swp
        exit 0
    fi

    ecrSwp=$(getEcrDev $swp )
    if [ -n "$ecrSwp" ]; then 
        echo $ecrSwp
    else
        lvSwp=$(composeLinkPath $dmSwp )
        [ -z "$lvSwp" ] && echo No LVM found, correct manually && exit 4
        swp=$(blkid -o device -t TYPE=LVM2 )
        if ! echo $swp | grep -q mapper; then
            echo $swp
        else
            getEcrDev $swp
        fi
    fi

}

getSwapDev
