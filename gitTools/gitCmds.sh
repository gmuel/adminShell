#!/bin/bash
if ! echo $PATH | grep -q '~/bin'; then
  export PATH="$PATH:~/bin"
fi
stripSpaces(){
  sed "s/\s\+/%/g"
}
getStripSpaces(){
  cut -d% -f$1
}
thirdCol(){
  stripSpaces | getStripSpaces 3
}
alias branch="git status | grep \"\(On branch\|Auf Branch\)\" | sed \"s/\(On branch \|Auf Branch \)//g\""
alias status="git status"
alias push="git push origin \$(branch )"
alias pull="git pull origin \$(branch )"
alias findBranch="git branch --list | grep"
modified(){
  git status | grep -v "\(both modified\|beide geändert\)" | grep "\(modified\|geändert\)" | thirdCol
}
bothMod(){
  git status | grep "\(both modified\|beide geändert\)" | thirdCol
}
renamed(){
  git status | grep "\(renamed\|umbenannt\)" | thirCol
}
updateBranch(){
  base_brnch=$2
  brnch=$1
  
  if [ -z "$base_brnch" ]; then
    echo "Missing source branch"
    return 1
  fi
  git checkout $base_brnch || return $?
  git pull origin $base_brnch
  git checkout $brnch
  
  git merge -m "$base_branch->$brnch update" $base_brnch
}
commit (){ git commit -m "[$(branch )] $@"; }
amend  (){ git commit --amend -m "[$(branch )] $@"; }
# findBranch(){
#  git branch --list | grep $1
# }

switchBranch(){
  brnch=$1
  [ -z "$brnch" ] && return 1
  if [ -z "$(findBranch $brnch )" ]; then
    git checkout -b $brnch
    return 0
  fi
  git checkout $brnch
}

addAll(){
  git add --all && git commit -m "[$(branch )] $@"
}

runBatch(){
  cmd=$1
  flg=$2
  
}
parent(){
    git branch --list | grep "\(main\|luks/mount\)" | sed "s/\* //g"
}
printDiff(){
    [ -z "$1" ] && cmd=modified || cmd="modified | grep \"\$1\""
#    echo $cmd
#    eval $cmd
    for i in $(eval $cmd ); do
        git diff $i
    done
}
