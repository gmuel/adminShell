#!/bin/bash
[ -z "$DB2CLIINIPATH" ] &&  source $(find ~ -type f -name startMQ_ACEShell.sh | head -1 )
ws=$1
[ -z "$ws" ] && echo no workspace given - aborting && return -1
bs=$2
[ -z "$bs" ] && bs=$(find ~ -type d -name GeneratedBarFiles | tail -1 ) # && ws=$(dirname $ws )/
buildApp(){
    br=${bs}/${1}.bar
    mqsipackagebar -a $br -w $ws -k $1
    echo $br
}

buildLib(){
    br=${bs}/${1}.bar
    mqsipackagebar -a $br -w $ws -y $1
    echo $br
}

build(){
    if [ -d ${ws}/$1 ] || [ -d ${ws}$1 ]; then
        dr=${ws/%'/'/}$1
        echo "~/git/eai_basic/$1 found"
        if [ -f $dr/library.descriptor ]; then
            buildLib $@
        else
            buildApp $@
        fi
    fi
}

compile(){
    mqsicreatebar -data $ws -b $2 -a $1 -compileOnly
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
