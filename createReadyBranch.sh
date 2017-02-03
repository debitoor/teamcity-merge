#!/bin/bash

set -e
timestamp=$(date +%s)
branch_name="ready/${GIT_BRANCH}/${timestamp}"

echo $branch_name

git config user.email $GIT_USER_EMAIL
git config user.name $GIT_USER_NAME

today=$(date +'%Y-%m-%d:00:00:00')
commit_today=$(git log -n 1 --since=${today})
if [ "${commit_today}" = "" ]
then
  git commit --allow-empty -m "trigger deploy"
  git push origin $GIT_BRANCH
fi

git checkout -b $branch_name
git push origin $branch_name
