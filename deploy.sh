#!/usr/bin/env bash
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


# Always last thing done before exit
_exit (){
	step_end
	exit $1
}


step_start "Checking branch is master"
if [ "$branch" = 'refs/heads/master' ]
then
    echo "master branch"
else
    echo "not master branch"
    exit 1
fi

step_start "Checking comitter is Teamcity"
comitter=`git log --pretty=format:'%cn' -n 1`
if [ "comitter" = 'Teamcity' ]
then
    echo "latest commit to master is by Teamcity"
else
    echo "latest commit to master is NOT by Teamcity"
    exit 1
fi

################################################
# Deploy to production
################################################

step_start "Deploying to production"
project=`cat package.json | grep "\"name\": \"" | sed 's/\s*"name": "//g' | sed 's/"//g' | sed 's/,//g' | sed 's/\s//g'`
hms deploy production-services "${project}" --no-log --retry || _exit $?

################################################
# Mark deploy on new relic
################################################
step_start "Tagging deploy on new relic"
author=`git log --pretty=format:'%an' -n 1`
curl -H "x-api-key:${NEW_RELIC_API_KEY}" -d "deployment[app_name]=${project}" -d "deployment[user]=${author}" -d "deployment[description]=${commitMessage}" https://api.newrelic.com/deployments.xml || _exit $?

################################################
# Add git tag and push to github
################################################

step_start "Adding git tag and pushing to github"
datetime=`date +%Y-%m-%d_%H-%M-%S`
git tag -a "${project}.production.${datetime}" -m "${commitMessage}" || _exit $?
git push origin --tags || _exit $?

