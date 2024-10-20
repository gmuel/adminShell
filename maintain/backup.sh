#!/bin/bash
source /home/gab2/bin/mountLuksDev.sh >> /dev/null
cd /home
dt_str=$(date +%Y%m%d)
parent_vol=$(btrs list ./ | grep -v "@$dt_str" | grep "@20\(2[4-9]\|[3-9][0-9]\)" | tail -1 | cut -d' ' -f9 )
if [ -z "$parent_vol" ]; then
    echo "No suitable subvol found for parent in /home"
    return -1
fi
echo Found parent volume /home/"$parent_vol"
child_vol=$(btrs list ./ | grep "@$dt_str" | tail -1 | cut -d' ' -f9 | sed "s/\(.\+\)/\/\1/g" | grep ".\+" || btrs snapshot -r /home "@$dt_str" | sed "s/.\+\.\(\/\@20\(2[4-9]\|[3-9][0-9]\)\(0[1-9]\|1[0-2]\)\(0[1-9]\|[12][0-9]\|3[01]\)\).\+/\1/g" )
# child_vol=$(echo "/@$(date +%Y%m%d )" | sed "s/.\+\.\(\/\@2024\(0[1-9]\|1[0-2]\)\)\(0[1-9]\|[12][0-9]\|3[01]\).\+/\1/g" )
echo "and new child volume /home$child_vol created"
backvol=
if inxi -M | grep XPS; then
    backvol=2
else
    backvol=1
fi
echo "backup subvol suffix found: $backvol"
UUID=
sbvl=
dvc=$(blkid | grep LUKS | grep "\(4c4656d9-9093-4bbc-9962-baf3c8cb8fe4\|62bc1b28-ab06-4e28-8167-2fe0e3c9499d\)" | sed "s/\(\/dev\/sd[a-z][23]\).\+/\1/g" )
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

