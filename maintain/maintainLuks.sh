#!/bin/bash

_helpfct(){
    cat << EOH
    $1 [options]
EOH
    case "$1" in
    "backupKeys") cat << EOH
        Backs up all .*.key files in /root/.keys
EOH
        ;;
   "backupAllHeaders") cat << EOH
        Backs up all available crypto_LUKS device headers to .root/crypt_headers
EOH
        ;;
    esac
    cat << EOH
        Options:
            -h/--help     print this message
            -v/--version  print version string
            -q            run commands quietly
            -n              
EOH
}
needHelp(){
    [[ "$1" == "-h" || "$1" == "--help" ]] && _helpfct "$2" $3
}
_version(){
    [[ "$1" == "-v" || "$1" == "--version" ]] && echo version 1.0.0
}
containsFlag(){
    declare -a args=( $@ )
    sz=${#args[@]}
    sz1=$(($sz-1))
    for i in ${args[@]:0:$sz1}; do
        [[ "$i" == "${args[$sz1]}" ]] && return 0
    done
    return 1
}
backupKeys(){
    needHelp "$1" "backupKeys" && return 0
    _version "$1" && return 0
    dr=.root/keys/
    qt=$(containsFlag $@ -q )
    dy=$(containsFlag $@ -n )
    for i in $(la /root/.keys/ ); do
        if [[ ! -f ${dr}$i && ! -f ${dr}${i//'.key'/'_key'} ]]; then
            [[ "$qt" == "0" ]] || echo backing up key $i
            [[ "$dy" == "0" ]] || cp /root/.keys/$i $dr
        fi
    done
}


backupAllHeaders(){
    needHelp "$1" "backupAllHeaders" && return 0
    dr=$(find /home -type d -name crypt_headers | head -1 )
    [ -z "$dr" ] && echo no backup dir found - aborting && return 1
    qt=$(containsFlag $@ -q )
    dy=$(containsFlag $@ -n )
    for i in $(blkid -o device -t TYPE=crypto_LUKS | grep -v sr0 )
    do          
        uuid=$(blkid -s UUID -o value $i )
        bckfl=${dr}.${uuid}.bin
        if [ ! -f $bckfl ]; then
            [[ "$qt" == "0" ]] || echo cryptsetup luksHeaderBackup $i --header-backup-file $bckfl
            [[ "$dy" == "0" ]] || cryptsetup luksHeaderBackup $i --header-backup-file $bckfl
        fi
    done
}
