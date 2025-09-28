#!/bin/bash
[ -z "$DB2CLIINIPATH" ] &&  source $(find ~ -type f -name startMQ_ACEShell.sh | head -1 )
ws=$1
[ -z "$ws" ] && ws=$(find ~ -type d -name GeneratedBarFiles | tail -1 ) # && ws=$(dirname $ws )/
buildApp(){
    mqsipackagebar -a ${ws}/${1}.bar -w ~/git/eai_basic/ -k $1
}

buildLib(){
    mqsipackagebar -a ${ws}/${1}.bar -w ~/git/eai_basic/ -y $1
}

build(){
    if [ -d ~/git/eai_basic/$1 ]; then
        if [ -f ~/git/eai_basic/${1}/library.descriptor ] || [ -f ~/git/eai_basic/${1}library.descriptor ]; then
            buildLib $@
        else
            buildApp $@
        fi
    fi
}

deploy(){
    mqsideploy $BRK -e $2 -a $1
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
