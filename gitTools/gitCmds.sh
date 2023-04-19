#!/bin/bash
if ! echo $PATH | grep -q '~/bin'; then
  export PATH="$PATH:~/bin"
fi
alias branch="git status | grep \"\(On branch\|Auf Branch\)\" | sed \"s/\(On branch \|Auf Branch \)//g\""
alias status="git status"
alias push="git push origin \$(branch )"
alias pull="git pull origin \$(branch )"
alias findBranch="git branch --list | grep"
alias modified='git status | grep -v "\(both modified\|beide geändert\)" | grep "\(modified\|geändert\)" | sed "s/\s\+/%/g" | cut -d % -f3'
alias bothMod='git status | grep "\(both modified\|beide geändert\)" | sed "s/\s\+/%/g" | cut -d % -f3'
updateBranch(){
  base_brnch=$2
  brnch=$1
  
  if [ -z "$base_brnch" ]; then
    echo "Missing source branch"
    exit 1
  fi
  git checkout $base_brnch || exit $?
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
  [ -z "$brnch" ] && exit 1
  if [ -z "$(findBranch $brnch )" ]; then
    git checkout -b $brnch
    exit 0
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

