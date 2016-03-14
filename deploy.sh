#!/bin/sh
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
	text = ${1/\n/%0A}
	curl -X POST \
		"https://slack.com/api/chat.postMessage?token=${SLACK_TOKEN}&channel=${SLACK_CHANNEL_ID}" \
		--data-urlencode "text=$symbol $text" \
		-s > /dev/null
}

# Always last thing done before exit
_exit (){
	step_end
	if [ "$1" = '0' ]
	then
		exit
	else
		slack "Deploy failure: $2\n${project}\n@${slackUser}\n${commitMessage}\n${buildUrl}" red
		exit $1
	fi
}

################################################
# Check that we are on master branch
################################################

step_start "Checking branch is master"
branch=`git rev-parse --abbrev-ref HEAD`
if [ "$branch" = 'master' ]
then
	echo "Master branch"
else
	echo "Error: Not master branch" >&2
	_exit 1 "Not master branch"
fi

##########################################################
# Check that the comitter is Teamcity (from a ready build)
##########################################################

step_start "Checking comitter is Teamcity"
comitter=`git log --pretty=format:'%cn' -n 1`
if [ "$comitter" = 'Teamcity' ]
then
	echo "Latest commit to master is by Teamcity"
else
	echo "Error: Latest commit to master is NOT by Teamcity" >&2
	_exit 1 "Latest commit to master is NOT by Teamcity"
fi

################################################
# Check that we have not already deployed
################################################

step_start "Checking that latest commit has no tag. If it has a tag it is already deployed"
git fetch --tags || _exit $? "Can not fet git tags"
returnValueWhenGettingTag=`git describe --exact-match --abbrev=0 2>&1 >/dev/null; echo $?`
if [ "$returnValueWhenGettingTag" = '0' ]
then
	echo "Master already has a tag, it is already deployed. Skipping deploy"
	_exit 0
else
	echo "Master has no tag yet, lets deploy (return value when getting tag: ${returnValueWhenGettingTag})"
fi

################################################
# Deploy to production
################################################
project=`node -e "console.log(require('./package.json').name || '')"`
heroku_project=`node -e "console.log(require('./package.json').heroku || require('./package.json').name)"`
deployscript=`node -e "console.log(require('./package.json').scripts.deploy || '')"`

old_school_deploy(){
	echo "WARNING: package.json has no deploy run-script. Using old school deploy. Please specify a script for npm run deploy"
	git push "ssh://git@heroku.com/${heroku_project}.git" HEAD:master --force || _exit $? "heroku deploy failed"
}
slackUser=$(`curl –silent -L 'https://raw.githubusercontent.com/debitoor/teamcity-merge/master/getGithubLastAuthor.sh' | bash`)
step_start "Deploying to production"
commitMessage=`git log -1 --pretty=%B`
LAST_COMMIT_AUTHOR=`git log --pretty=format:'%an' -n 1`
if [ "$deployscript" = '' ]
then
	old_school_deploy
else
	npm run deploy || _exit $? "npm run deploy failed"
fi
slack "Success deploying ${project}\n@${slackUser}\n${commitMessage}\n${commitUrl}${mergeCommitSha}" green

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
