#!/bin/bash

DT_PAT="20\(2[5-9]\|3[0-9]\)\(\(0[1-9]\|1[012]\)\(0[1-9]\|[12][0-9]\)\|\(\(0[13-9]\|1[0-2]\)30\)\|\(\(0[13578]\|1[02]\)31\)\)"

btr(){
	btrfs $@
}

btrs(){
	btr sub $@
}

listBtrs(){
	btrs list $1
}

awkN(){
    awk "{print \$$1}"
}



listByPat(){
	listBtrs $1 | grep "$2"
}
listByLevel(){
	listByPat $1 "level $2"
}

get2ndCol(){
	awkN 2
}

get9thCol(){
	awkN 9
}

getLastByLevel(){
	listByLevel $1 $2 | tail -1
}

listAllButLast(){
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		cat << EOH

 listAllButLast BTRFS-DIR VOL-PATTERN [MATCH-PATTERN]

	List all but last subvolumes for BTRFS-DIR matching VOL-PATTERN and MATCH-PATTERN

	BTRFS-DIR		-	btrfs mount point
	VOL-PATTERN		-	subvolume match pattern, usually the subvol name - like /var "var\$",
						/ "root\$", ...
	MATCH-PATTERN	-	optional, filter matches through this filter, defaults to \$DT_PAT, use dot '.' 
						for complete list
	

	Options:	-h/--help	print this message

	Exit codes:	-1	empty subvolume id, i.e. no matching subvol found
				see btrfs subvolume sub commands, 
EOH
		return 0
	fi
	vol_id=$(listByPat $1 "$2" | get2ndCol | head -1 )
	[ -z "$vol_id" ] && return -1
	pat=${3:-$DT_PAT}
	declare -a vls=( $(listByLevel $1 $vol_id | grep "$pat" | get9thCol ) )
	sz=${#vls[@]}
	for((i=0;i<sz-1;i++)); do
		echo ${vls[$i]}
	done
}
