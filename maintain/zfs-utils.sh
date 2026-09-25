#!/bin/bash

listAllDSs(){
    zfs get ${2:-encryption} -${4:-""}Ht ${3:-filesystem} -o name,value $1
}
getProp(){
    listAllDSs $1 $2 $3
}
listAllDSnCl(){
    listAllDSs $1 origin filesystem r
}
listNonCloneDS(){
    listAllDSnCl $1 | awk '{if($2 == "-"){print $1}}'
}
listCloneDS(){
    listAllDSnCl $1 | awk '{if($2 != "-"){print $1}}'
}
listAllSnaps(){
    listAllDSs $1 origin snapshot | awk '{print $1}'
}
firstSnap(){
    listAllSnaps $1 | head -${2:-1}
}
lastSnap(){
    listAllSnaps $1 | tail -${2:-1}
}
