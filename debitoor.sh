#!/bin/bash
npmpath=`which npm`
alias npm="node --max_old_space_size=8000 ${npmpath}"

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

slack(){
	if [ "$2" = 'green' ]
	then
		symbol="✅"
	elif [ "$2" = 'yellow' ]
	then
		symbol="❗"
	elif [ "$2" = 'red' ]
	then
		symbol="❌"
	fi
	curl -X POST \
		"https://slack.com/api/chat.postMessage?token=${SLACK_TOKEN}&channel=${SLACK_CHANNEL_ID}" \
		--data-urlencode "text=$symbol $1" \
		-s > /dev/null
}

# Always last thing done after merge (fail or success)
delete_ready_branch (){
	step_start "Deleting ready branch on github"
	git push origin ":ready/${branch}"
	step_end
	if [ "$1" = '0' ]
	then
		if [ "$2" != '' ]
		then
			slack "$2
${project}
@${slackUser}
${commitMessage}
${buildUrl}" yellow
			message=`echo "$2
${project}
@${slackUser}
${commitMessage}
${buildUrl}"`
		else
			slack "Success merging ${project}
@${slackUser}
${commitMessage}
${commitUrl}${mergeCommitSha}" green
			message=`echo "Success merging ${project}
@${slackUser}
${commitMessage}
${commitUrl}${mergeCommitSha}"`
			deploy
		fi
	else
		slack "Failure merging: $2
${project}
@${slackUser}
${commitMessage}
${buildUrl}" red
		message=`echo "Failure merging: $2
${project}
@${slackUser}
${commitMessage}
${buildUrl}"`
	fi
	echo "
${message}"
	exit $1
}

# Always last thing done before exit
_exit (){
	step_end
	if [ "$1" = '0' ]
	then
		exit
	else
		slack "Failure: $2
${project}
@${slackUser}
${commitMessage}
${buildUrl}" red
		exit $1
	fi
}

project=`node -e "console.log(require('./package.json').name || '')"`
if [ "$project" = 'Debitoor' ]
then
	project="debitoor-mobile-next"
fi

heroku_project=`node -e "console.log(require('./package.json').heroku || require('./package.json').name)"`
slackUser=$(curl –s -L 'https://raw.githubusercontent.com/debitoor/teamcity-merge/master/getGithubLastAuthor.sh' | bash)

old_school_deploy(){
	echo "WARNING: package.json has no deploy run-script. Using old school deploy. Please specify a script for npm run deploy"
	git push "ssh://git@heroku.com/${heroku_project}.git" HEAD:master --force || _exit $? "heroku deploy failed"
}

deploy(){
	################################################
	# Deploy to production
	################################################

	step_start "Deploying to production"
	commitMessage=`git log -1 --pretty=%B`
	LAST_COMMIT_AUTHOR=`git log --pretty=format:'%an' -n 1`
	deployscript=`node -e "console.log(require('./package.json').scripts.deploy || '')"`
	if [ "$deployscript" = '' ]
	then
		old_school_deploy
	else
		npm run deploy || _exit $? "npm run deploy failed"
	fi
	slack "Success deploying ${project}
@${slackUser}
${commitMessage}
${commitUrl}${mergeCommitSha}" green

	################################################
	# Add git tag and push to GitHub
	################################################

	step_start "Adding git tag and pushing to GitHub"
	git config user.email "debitoor-bot@debitoor.com" || _exit $? "Could not set git user.email"
	git config user.name "Teamcity" || _exit $? "Could not set git user.name"
	datetime=`date +%Y-%m-%d_%H-%M-%S`
	git tag -a "${project}.production.${datetime}" -m "${commitMessage}" || _exit $? "Could not create git tag"
	git push origin --tags || _exit $? "Could not push git tag to GitHub"

	_exit 0
}

commitMessage="${branch}"
git config user.email "debitoor-bot@debitoor.com" || delete_ready_branch $? "Could not set git email"
git config user.name "Teamcity" || delete_ready_branch $? "Could not set git user name"

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
		# Avoid -i flag for sed, because of platform differences
		sed 's/\[remote \"origin\"\]/[remote "origin"]\
		fetch = +refs\/pull\/*\/head:refs\/remotes\/origin\/pullrequest\/*/g' .git/config >.git/config_with_pull_request
		cp .git/config .git/config.backup
		mv .git/config_with_pull_request .git/config
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


	error='
Did you try to deploy a branch that is not a pull request?
Or did you forget to push your changes to github?'

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
# Updates texts in ready branch
#####################################################################

if [ "$1" = 'texts' ]
then
	step_start "Updates texts in ready branch"
	npm run update-texts || echo "No update-texts NPM script"
	git add package.json
	git commit -m "updates texts" || echo "No new texts"
fi

#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard, clean -fx)
# And pull master
#####################################################################

step_start "Checking out master, resetting (hard), pulling from origin and cleaning"

git checkout master || delete_ready_branch $? "Could not checkout master"
git reset --hard origin/master || delete_ready_branch $? "Could not reset to master"
git pull || delete_ready_branch $? "Could not pull master"
git clean -fx || delete_ready_branch $? "Could not git clean on master"

#####################################################################
# Merge latests texts to master branch
#####################################################################

#if [ "$1" = 'texts' ]
#then
#	step_start "Merge latests texts to master branch"
#
#	git merge origin/texts --squash -X theirs || delete_ready_branch $? "Could not merge latest texts to master"
#	git checkout source/texts/translations.json --theirs || delete_ready_branch $? "Could not checkout translations.json (master)"
#	git add source/texts/translations.json || delete_ready_branch $? "Could not git add translations.json to master"
#	git commit -m 'merged latest texts' || echo "ignoring nothing to commit, continuing"
#fi

################################################
# Merge into master
# You will want to use you own email here
################################################

case ${branch} in
merge_latest_texts*)
	step_start "Branch name starts with merge_latest_texts - skipping merging ready branch into master"
	;;
*)
	step_start "Merging ready branch into master, with commit message that closes pull request number ${PR_NUMBER}"

	message_on_commit_error(){
		commitErrorCode=$1
		echo 'Commiting changes returned an error (status: ${commitErrorCode}). We are assuming that this is due to no changes, and exiting gracefully'
		delete_ready_branch 0 "No changes in ready build"
	}

	git merge --squash "ready/${branch}" || delete_ready_branch $? "Merge conflicts (could not merge)"
	branchWithUnderscore2SpacesAndRemovedTimestamp=`echo "${branch}" | sed -e 's/_/ /g' | sed -e 's/\/[0-9]*s$//g'`
	if [ "$PR_NUMBER" = 'none' ]
	then
		commitMessage="${branchWithUnderscore2SpacesAndRemovedTimestamp}"
	else
		commitMessage="fixes #${PR_NUMBER} - ${branchWithUnderscore2SpacesAndRemovedTimestamp}"
	fi
	echo "Committing squashed merge with message: \"${message}\""
	git commit -m "${commitMessage}" --author "${LAST_COMMIT_AUTHOR}" || message_on_commit_error $?
	;;
esac

mergeCommitSha=`git log -1 --format="%H"`



################################################
# Check npm version
################################################
npmSpecified=`cat package.json | jsonfilter "engines.npm" | sed -e 's/"//g'`
npmCurrent=`npm --version`
if [ "${npmSpecified}" != "${npmCurrent}" ]
then
	delete_ready_branch 1 "Current npm version is ${npmCurrent}. It does not match the npm version in package.json ${npmSpecified}"
fi

################################################
# Check node.js version
################################################
nodeSpecified=`cat package.json | jsonfilter "engines.node" | sed -e 's/"//g'`
nodeCurrent=`node --version | sed -e 's/v//g'`
if [ "${nodeSpecified}" != "${nodeCurrent}" ]
then
	delete_ready_branch 1 "Current node.js version is ${nodeCurrent}. It does not match the node.js version in package.json ${nodeSpecified}"
fi

################################################
# Run tests
################################################

step_start "Running tests with >npm run teamcity "

## file descriptor 5 is stdout
exec 5>&1
## redirect stderr to stdout for capture by tee, and redirect stdout to file descriptor 5 for output on stdout (with no capture by tee)
## after capture of stderr on stdout by tee, redirect back to stderr
npm run teamcity 2>&1 1>&5 | tee err.log 1>&2

## get exit code of "npm run teamcity"
code="${PIPESTATUS[0]}"
err=$(cat err.log && rm -f err.log)
if [ "${code}" != 0 ]
then
	delete_ready_branch "${code}" "Failing test(s)
	${err}"
fi

################################################
# Push changes to github
################################################

step_start "Pushing changes to github master branch"

git push origin master || delete_ready_branch $? "Could not push changes to GitHub"

delete_ready_branch 0
