#!/bin/sh
if [ "$branch" = 'refs/heads/master' ]
then
    echo "master branch, doing nothing"
    exit 0
fi

################################################
# Make sure git fetches (hidden) Pull Requests
# by adding:
# fetch = +refs/pull/*/head:refs/remotes/origin/pullrequest/*
# to .git/config under the origin remote
################################################

echo "\nAdding fetch of pull requests to .git/config"

CURRENT_FETCH=`grep '	fetch =.\+refs/pull/\*/head:refs/remotes/origin/pullrequest/\*' .git/config`
if [ "$CURRENT_FETCH" = '' ]
then
	sed -i 's/\[remote \"origin\"\]/[remote "origin"]\
	fetch = +refs\/pull\/*\/head:refs\/remotes\/origin\/pullrequest\/*/g' .git/config
	echo 'Added fetch of pull request to .git/config:'
	cat .git/config
else
	echo 'Fetch of pull request already in place in .git/config'
fi
git fetch --prune || exit $?

########################################################################################
# Lookup PR number
# By looking the SHA checksum of the current branchs latests commit
# And finding a pull request that has a matching SHA checksum as the lastest commit
# This enforces a restriction that you can only merge branches that match a pull request
# And using the number of the pull request later, we can close the pull request
# by making the squash merge commit message include "fixes #[pull request number] ..."
########################################################################################

echo "\nFinding pull request that matches branch we want to merge (current branch)"

CURRENT_SHA=`git log -1 --format="%H"`
echo "Current SHA:"
echo "${CURRENT_SHA}"

LAST_COMMIT_AUTHOR=`git log --pretty=format:'%an' -n 1`
echo "This will be the author of the merge commit in master: ${LAST_COMMIT_AUTHOR} (the last commit in branch was done by this person)"

error='\nDid you try to deploy a branch that is not a pull request?\nOr did you forget to push your changes to github?'

MATCHING_PULL_REQUEST=`git show-ref | grep $CURRENT_SHA | grep 'refs/remotes/origin/pullrequest/'`
if [ "$MATCHING_PULL_REQUEST" = '' ] ; then
  echo "Error finding matching pull request: ${error}" >&2; exit 1
fi
echo "Matching pull request:"
echo "${MATCHING_PULL_REQUEST}"

PR_NUMBER=`echo "${MATCHING_PULL_REQUEST}" | sed 's/[0-9a-z]* refs\/remotes\/origin\/pullrequest\///g' | sed 's/\s//g'`
echo "Extracted pull request number:"
echo "${PR_NUMBER}"
case ${PR_NUMBER} in
    ''|*[!0-9]*) echo "Error pull request number does not match number regExp (weird!): ${error}" >&2; exit 1 ;;
    *) echo "Success. Pull request number passes regExp test for number. Exporting PR_NUMBER=${PR_NUMBER}" ;;
esac

#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard)
# And pull master
#####################################################################

echo "\nChecking out, resetting (hard) and pulling master branch"

git checkout master || exit $?
git reset --hard origin/master || exit $?
git pull || exit $?

################################################
# Merge into master
# You will want to use you own email here
################################################

echo "\nMerging ready branch into master, with commit message that closes pull request number ${PR_NUMBER}"

git config user.email "teamcityagent@e-conomic.com" || exit $?
git config user.name "Teamcity" || exit $?
git merge --squash "origin/ready/${branch}" || exit $?
branchWithUnderscore2SpacesAndRemovedTimestamp=`echo "${branch}" | sed -e 's/_/ /g' | sed -e 's/\/[0-9]*s$//g'`
commitMessage="fixes #${PR_NUMBER} - ${branchWithUnderscore2SpacesAndRemovedTimestamp}"
echo "Committing squashed merge with message: \"${message}\""
git commit -m "${commitMessage}" --author "${LAST_COMMIT_AUTHOR}" || exit $?

################################################
# Run tests
################################################

npm run teamcity || exit $?

################################################
# Push changes to github
################################################

git push origin master || exit $?

################################################
# Deploy to production
################################################

project=`cat package.json | grep "\"name\": \"" | sed 's/\s*"name": "//g' | sed 's/"//g' | sed 's/,//g' | sed 's/\s//g'`

hms deploy production-services "${project}" --no-log --retry || exit $?

################################################
# Add git tag and push to github
################################################

datetime=`date +%Y-%m-%d-%H-%M-%S`
git tag -a "${project}.production.${datetime}" -m "${commitMessage}" || exit $?
git push origin --tags || exit $?