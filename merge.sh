#!/bin/sh
if [ "$branch" = 'refs/heads/master' ]
then
    echo "master branch, doing nothing"
    exit 0
fi

### Step helper functions
stepName=""
step_end(){
	echo "##teamcity[blockClosed name='${stepName}']"
}
step_start(){
	if [ "${stepName}" != '' ]
	then
		step_end
	fi
	stepName=`echo "-- $1 --"`
	echo "##teamcity[blockOpened name='${stepName}']"
}


# Always last thing done before exit
delete_ready_branch (){
	step_start "Deleting ready branch on github"
	git push origin ":ready/${branch}"
	step_end
	exit $1
}

step_start "Finding author"

LAST_COMMIT_AUTHOR=`git log --pretty=format:'%an' -n 1`
echo "This will be the author of the merge commit in master: ${LAST_COMMIT_AUTHOR} (the last commit in branch was done by this person)"


case ${branch} in
*_no_pull_request)
  ## If the ready branch ends with "_no_pull_request" we will not try to match to a pull request. This is for merging latest texts
  step_start "No pull request - Git fetching"
  PR_NUMBER="none"
  git fetch --prune || delete_ready_branch $?
  ;;
*)
	################################################
	# Make sure git fetches (hidden) Pull Requests
	# by adding:
	# fetch = +refs/pull/*/head:refs/remotes/origin/pullrequest/*
	# to .git/config under the origin remote
	################################################

	step_start "Adding fetch of pull requests to .git/config"

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
	git fetch --prune || delete_ready_branch $?

	########################################################################################
	# Lookup PR number
	# By looking the SHA checksum of the current branchs latests commit
	# And finding a pull request that has a matching SHA checksum as the lastest commit
	# This enforces a restriction that you can only merge branches that match a pull request
	# And using the number of the pull request later, we can close the pull request
	# by making the squash merge commit message include "fixes #[pull request number] ..."
	########################################################################################

	step_start "Finding pull request that matches current branch"

	CURRENT_SHA=`git log -1 --format="%H"`
	echo "Current SHA:"
	echo "${CURRENT_SHA}"


	error='\nDid you try to deploy a branch that is not a pull request?\nOr did you forget to push your changes to github?'

	MATCHING_PULL_REQUEST=`git show-ref | grep $CURRENT_SHA | grep 'refs/remotes/origin/pullrequest/'`
	if [ "$MATCHING_PULL_REQUEST" = '' ] ; then
	  echo "Error finding matching pull request: ${error}" >&2; delete_ready_branch 1
	fi
	echo "Matching pull request:"
	echo "${MATCHING_PULL_REQUEST}"

	PR_NUMBER=`echo "${MATCHING_PULL_REQUEST}" | sed 's/[0-9a-z]* refs\/remotes\/origin\/pullrequest\///g' | sed 's/\s//g'`
	echo "Extracted pull request number:"
	echo "${PR_NUMBER}"
	case ${PR_NUMBER} in
		''|*[!0-9]*) echo "Error pull request number does not match number regExp (weird!): ${error}" >&2; delete_ready_branch 1 ;;
		*) echo "Success. Pull request number passes regExp test for number. Exporting PR_NUMBER=${PR_NUMBER}" ;;
	esac
	;;
esac
#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard)
# And pull master
#####################################################################

step_start "Checking out, resetting (hard) and pulling master branch"

git checkout master || delete_ready_branch $?
git reset --hard origin/master || delete_ready_branch $?
git pull || delete_ready_branch $?

################################################
# Merge into master
# You will want to use you own email here
################################################

step_start "Merging ready branch into master, with commit message that closes pull request number ${PR_NUMBER}"

message_on_commit_error(){
	commitErrorCode=$1
	echo 'Commiting changes returned an error (status: ${commitErrorCode}). We are assuming that this is due to no changes, and continuing'
}

git config user.email "teamcity@e-conomic.com" || delete_ready_branch $?
git config user.name "Teamcity" || delete_ready_branch $?
git merge --squash "origin/ready/${branch}" || delete_ready_branch $?
branchWithUnderscore2SpacesAndRemovedTimestamp=`echo "${branch}" | sed -e 's/_/ /g' | sed -e 's/\/[0-9]*s$//g'`
if [ "$PR_NUMBER" = 'none' ]
then
	commitMessage="${branchWithUnderscore2SpacesAndRemovedTimestamp}"
else
	commitMessage="fixes #${PR_NUMBER} - ${branchWithUnderscore2SpacesAndRemovedTimestamp}"
fi
echo "Committing squashed merge with message: \"${message}\""
git commit -m "${commitMessage}" --author "${LAST_COMMIT_AUTHOR}" || message_on_commit_error $?

################################################
# Run tests
################################################

step_start "Running tests with >npm run teamcity "

npm run teamcity || delete_ready_branch $?

################################################
# Push changes to github
################################################

step_start "Pushing changes to github master branch"

git push origin master || delete_ready_branch $?

delete_ready_branch
