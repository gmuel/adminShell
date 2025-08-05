#!/bin/bash
backupKeys(){
    dr=.root/keys/
    for i in $(la /root/.keys/ ); do
        if [[ ! -f ${dr}$i && ! -f ${dr}${i//'.key'/'_key'} ]]; then
            cp /root/.keys/$i $dr
        fi
    done
}


backupAllHeaders(){
    for i in $(blkid -o device -t TYPE=crypto_LUKS | grep -v sr0 )
    do
        uuid=$(blkid -s UUID -o value $i )
        dr=.root/crypt_headers/home/
        bckfl=${dr}.${uuid}.bin
        if [ ! -f $bckfl ]; then
            echo cryptsetup luksHeaderBackup $i --header-backup-file $bckfl
            cryptsetup luksHeaderBackup $i --header-backup-file $bckfl
        fi
    done
}
