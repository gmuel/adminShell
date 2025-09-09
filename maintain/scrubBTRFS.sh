#!/bin/bash

bscr(){
    btrfs scrub start $1
}
bsct(){
    btrfs scrub status $1
}


if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EOH
$0 [options] PATH/TO/MOUNTED/BTRFS/ [PATH/TO/MOUNTED/BTRFS/ ...]

    Initialize btrfs scrub start command on list of BTRFS fs's
    and print out status for device for further analysis

    Options:
        -h/--help print this message
        -v/--version print version string

    Args:
        List of mounted BTRFS systems, at least one arg is required

    Exit codes:
        last exit code of status call, see btrfs scrub doc

EOH

    exit 0
fi


if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    echo version 1.0.1
    exit 0
fi

for i in $@; do
    bsct $i | grep "\(no stats\|finished\)" && bscr $i
    finished=1
    for((j=0;j<240;j++)); do
        sleep 15s
        bsct $i | grep finished && finished=0 && break
    done
    [ $finished ] && bsct $i || echo scrub task not yet completed for mount point $i
done

