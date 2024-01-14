#!/bin/bash
source /home/gab2/bin/mountLuksDev.sh # >> /dev/null
cd /home
dt_str=$(date +%Y%m%d)
parent_vol=$(btrs list ./ | grep -v "$dt_str" | tail -1 | cut -d' ' -f9 )
echo Found parent volume /home/"$parent_vol"
child_vol=$(btrs list ./ | grep "$dt_str" | tail -1 | cut -d' ' -f9 | sed "s/\(.\+\)/\/\1/g" | grep ".\+" || btrs snapshot -r /home "@$dt_str" | sed "s/.\+\.\(\/\@2024\(0[1-9]\|1[0-2]\)\(0[1-9]\|[12][0-9]\|3[01]\)\).\+/\1/g" )
# child_vol=$(echo "/@$(date +%Y%m%d )" | sed "s/.\+\.\(\/\@2024\(0[1-9]\|1[0-2]\)\)\(0[1-9]\|[12][0-9]\|3[01]\).\+/\1/g" )
echo and new child volume /home"$child_vol" created
backvol=$(inxi -Fzx | grep -q XPS && echo 2 || echo 1 )
UUID=
sbvl=
dvc=$(blkid | grep LUKS | grep "sd[a-z][12]" | sed "s/\(\/dev\/sd[a-z][12]\).\+/\1/g" )
echo $dvc used as backup
UUID=$(blkid -s UUID -o value $dvc )
echo having UUID $UUID
sbvl="$(grep $UUID /home/gab2/bin/backup.map | cut -d' ' -f2 )$backvol"
echo backup subvol found: $sbvl
if [ ! -z "$sbvl" ]; then 
    dvc=$(echo $dvc | sed "s/\/dev\///g" )
    mountLuksDev $dvc gab2 $sbvl
    if [ "$?" -eq "0" ]; then
        echo backup subvol mounted
        dr=/media/gab2/$UUID
        if btrs list $dr | grep "$parent_vol"; then
            btr send -p "/home/$parent_vol" "/home$child_vol" | btr receive $dr && \
                echo "Child vol: \"/home$child_vol\" of parent vol: \"/home/$parent_vol\" sent to '$dr'"
        fi
        umountLuksDev $dvc gab2
    fi
fi

