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

gitter(){
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
	curl -X POST -i -H "Content-Type: application/json" \
		-H "Accept: application/json" \
		-H "Authorization: Bearer ${GITTER_TOKEN}" "https://api.gitter.im/v1/rooms/555c7bea15522ed4b3e0ab08/chatMessages" \
		-d "{\"text\":\"$symbol $1\"}" \
		-s
}

# Always last thing done before exit
_exit (){
	step_end
	gitterUser=`echo "${LAST_COMMIT_AUTHOR}" | sed 's/\s//g'`
	if [ "$1" = '0' ]
	then
		exit
	else
		gitter "Deploy failure: $2\n${project}\n@${gitterUser}\n${commitMessage}\n${buildUrl}" red
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
heroku_project=`node -e "console.log(require('./package.json').heroku || '')"`
deployscript=`node -e "console.log(require('./package.json').deploy || '')"`
project=`node -e "console.log(require('./package.json').name || '')"`

old_school_deploy(){
	echo "WARNING: package.json has no deploy run-script. Using old school deploy. Please specify a script for npm run deploy"
	if [ "$heroku_project" = '' ]
	then
		git push "ssh://git@heroku.com/${heroku_project}.git" HEAD:master --force || _exit $? "heroku deploy failed"
	else
		hms deploy production-services "${project}" --no-log --retry || _exit $? "hms deploy failed"
	fi
}

step_start "Deploying to production"
commitMessage=`git log -1 --pretty=%B`
LAST_COMMIT_AUTHOR=`git log --pretty=format:'%an' -n 1`
if [ "$deployscript" = '' ]
then
	old_school_deploy
else
	npm run deploy || _exit $? "npm run deploy failed"
fi
gitter "Success deploying ${project}\n@${gitterUser}\n${commitMessage}\n${commitUrl}${mergeCommitSha}" green

################################################
# Add git tag and push to GitHub
################################################

step_start "Adding git tag and pushing to GitHub"
git config user.email "debitoor-bot@debitoor.com" || _exit $? "Could not set git user.email"
git config user.name "Teamcity" || _exit $? "Could not set git user.name"
datetime=`date +%Y-%m-%d_%H-%M-%S`
git tag -a "${project}.production.${datetime}" -m "${commitMessage}" || _exit $? "Could not create git tag"
git push origin --tags || _exit $? "Could not push git tag to GitHub"

################################################
# Mark deploy on New Relic
################################################

step_start "Marking deploy on New Relic"
author=`git log --pretty=format:'%an' -n 1`
curl -H "x-api-key:${NEW_RELIC_API_KEY}" -d "deployment[app_name]=${project}" -d "deployment[user]=${author}" -d "deployment[description]=${commitMessage}" https://api.newrelic.com/deployments.xml || _exit $? "Could not tag deploy in New Relic"
_exit 0
