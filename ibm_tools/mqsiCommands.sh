#!/bin/bash
ws=$1
[ -z "$ws" ] && ws=$(find ~ -type d -name GeneratedBarFiles | tail -1 ) # && ws=$(dirname $ws )/
buildApp(){
    mqsipackagebar -a ${ws}/${1}.bar -w ~/git/eai_basics/ -k $1
}

buildLib(){
    mqsipackagebar -a ${ws}/${1}.bar -w ~/git/eai_basics/ -y $1
}

build(){
    if [ -d ~/git/eai_basics/$1 ]; then
        if [ -f ~/git/eai_basics/${1}/library.descriptor ] || [ -f ~/git/eai_basics/${1}library.descriptor ]; then
            buildLib $1
        else
            buildApp $1
        fi
    fi
}

deploy(){
    mqsideploy $BRK -e default -a $1
}


overrideBar(){
    for i in $(mqsireadbar -b $1 -r | grep "\$[a-zA-Z0-9.\-\_]\+" | sed "s/\s\+/ /g" | cut -d' ' -f2 ); do
        val=$(mqsireadbar -b $1 -r | grep $i | sed "s/\s\+/ /g" | cut -d' ' -f4 )
        if echo "$val" | grep '$USER'; then
            val=${val//'$USER'/"$USER"}
        else
            val=junitenv
        fi
        echo $val
        arti=$(basename $1 )
        arti=${arti//'.bar'/}
        mqsiapplybaroverride -b $1 -k $arti -m $i=$val
    done
}
