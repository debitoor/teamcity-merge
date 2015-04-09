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

hipchat(){
	curl -H "Content-Type: application/json" \
		 -X POST \
		 -d "{\"color\": \"purple\", \"message_format\": \"text\", \"message\": \"$1\" }" \
		 "https://api.hipchat.com/v2/room/807962/notification?auth_token=${HIPCHAT_API_KEY}"
}

# Always last thing done before exit
delete_ready_branch (){
	step_start "Deleting ready branch on github"
	git push origin ":ready/${branch}"
	step_end
	hipchatUser=`echo "${LAST_COMMIT_AUTHOR}" | sed 's/\s//g'`
	if [ "$1" = '0' ]
	then
		if [ "$2" != '' ]
		then
			hipchat "$2: ${project}\n@${hipchatUser}\n${commitMessage}"
		else
			hipchat "Success merging: ${project}\n@${hipchatUser}\n${commitMessage}"
		fi
	else
		hipchat "Failure merging: $2 - ${project}\n@${hipchatUser}\n${commitMessage}"
	fi
	exit $1
}
project=`cat package.json | grep "\"name\": \"" | sed 's/\s*"name": "//g' | sed 's/"//g' | sed 's/,//g' | sed 's/\s//g'`
commitMessage="${branch}"

step_start "Finding author"

LAST_COMMIT_AUTHOR=`git log --pretty=format:'%an' -n 1`

echo "This will be the author of the merge commit in master: ${LAST_COMMIT_AUTHOR} (the last commit in branch was done by this person)"


case ${branch} in
*_no_pull_request)
  ## If the ready branch ends with "_no_pull_request" we will not try to match to a pull request. This is for merging latest texts
  step_start "No pull request - Git fetching"
  PR_NUMBER="none"
  git fetch --prune || delete_ready_branch $? "Could not git fetch"
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
	git fetch --prune || delete_ready_branch $? "Could not git fetch"

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
	  echo "Error finding matching pull request: ${error}" >&2; delete_ready_branch 1 "Could not find matching pull request"
	fi
	echo "Matching pull request:"
	echo "${MATCHING_PULL_REQUEST}"

	PR_NUMBER=`echo "${MATCHING_PULL_REQUEST}" | sed 's/[0-9a-z]* refs\/remotes\/origin\/pullrequest\///g' | sed 's/\s//g'`
	echo "Extracted pull request number:"
	echo "${PR_NUMBER}"
	case ${PR_NUMBER} in
		''|*[!0-9]*) echo "Error pull request number does not match number regExp (weird!): ${error}" >&2; delete_ready_branch 1 "Could not find pull request number";;
		*) echo "Success. Pull request number passes regExp test for number. Exporting PR_NUMBER=${PR_NUMBER}" ;;
	esac
	;;
esac

#####################################################################
# Merge latests texts to ready branch
#####################################################################

step_start "Merge latests texts to ready branch"

git fetch origin texts || delete_ready_branch $? "Could not fetch texts branch"
git config user.email "teamcity@e-conomic.com" || delete_ready_branch $? "Could not set git email"
git config user.name "Teamcity" || delete_ready_branch $? "Could not set git user name"
git config merge.renamelimit 999999 || delete_ready_branch $? "Could not set git renamelimit"
git merge origin/texts --squash -X theirs || delete_ready_branch $? "Could not merge latest texts"
git checkout source/texts/translations.json --theirs || delete_ready_branch $? "Could not checkout translations.json"
git add source/texts/translations.json || delete_ready_branch $? "Could not git add translations.json"
git commit -m 'merged latest texts' || echo "ignoring nothing to commit, continuing"
git push origin "ready/${branch}" || delete_ready_branch $? "Could push commit with latests texts to GitHub"

#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard, clean -fx)
# And pull master
#####################################################################

step_start "Checking out master, resetting (hard), pulling from origin and cleaning"

git checkout master || delete_ready_branch $?  "Could not checkout master"
git reset --hard origin/master || delete_ready_branch $? "Could not reset to master"
git pull || delete_ready_branch $? "Could not pull master"
git clean -fx || delete_ready_branch $? "Could not git clean on master"

#####################################################################
# Merge latests texts to master branch
#####################################################################

step_start "Merge latests texts to master branch"
git merge origin/texts --squash -X theirs || delete_ready_branch $? "Could not merge latest texts to master"
git checkout source/texts/translations.json --theirs || delete_ready_branch $? "Could not checkout translations.json (master)"
git add source/texts/translations.json || delete_ready_branch $? "Could not git add translations.json to master"
git commit -m 'merged latest texts' || echo "ignoring nothing to commit, continuing"

################################################
# Merge into master
# You will want to use you own email here
################################################

step_start "Merging ready branch into master, with commit message that closes pull request number ${PR_NUMBER}"

message_on_commit_error(){
	commitErrorCode=$1
	echo 'Commiting changes returned an error (status: ${commitErrorCode}). We are assuming that this is due to no changes, and exiting gracefully'
	delete_ready_branch 0 "No changes in ready build"
}

git merge --squash "origin/ready/${branch}" || delete_ready_branch $? "Merge conflicts (could not merge)"
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

npm run teamcity || delete_ready_branch $? "Failing test(s)"

################################################
# Push changes to github
################################################

step_start "Pushing changes to github master branch"

git push origin master || delete_ready_branch $? "Could not push changes to GitHub"

delete_ready_branch 0
