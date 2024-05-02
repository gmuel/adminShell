if [ -z "$BRK" ]; then
    . ~/bin/startMQ_ACEShell.sh
fi
createBar(){
    declare -a args=( $@ )
    libs=
    if [[ ${#args[@]} >= 3 ]]; then
        libs="-l ${args[@]:2}"
    fi
    mqsicreatebar -data ${args[0]} -a ${args[1]} -compileOnly  $libs
}
packageBar(){
    mqsipackagebar $@
}

deploy(){
    mqsideploy $BRK -e $1 -k $2 -w $3
}
