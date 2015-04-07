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
    _exit 1
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
    _exit 1
fi

################################################
# Check that we have not already deployed
################################################

step_start "Checking that latest commit has no tag. If it has a tag it is already deployed"
git fetch --tags || _exit $?
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

step_start "Deploying to production"
commitMessage=`git log -1 --pretty=%B`
project=`cat package.json | grep "\"name\": \"" | sed 's/\s*"name": "//g' | sed 's/"//g' | sed 's/,//g' | sed 's/\s//g'`
hms deploy production-services "${project}" --no-log --retry || _exit $?
sh hipchat.sh "Success deploying ${project} ${commitMessage}"

################################################
# Add git tag and push to GitHub
################################################

step_start "Adding git tag and pushing to GitHub"
git config user.email "teamcity@e-conomic.com" || _exit $?
git config user.name "Teamcity" || _exit $?
datetime=`date +%Y-%m-%d_%H-%M-%S`
git tag -a "${project}.production.${datetime}" -m "${commitMessage}" || _exit $?
git push origin --tags || _exit $?

################################################
# Mark deploy on New Relic
################################################

step_start "Marking deploy on New Relic"
author=`git log --pretty=format:'%an' -n 1`
curl -H "x-api-key:${NEW_RELIC_API_KEY}" -d "deployment[app_name]=${project}" -d "deployment[user]=${author}" -d "deployment[description]=${commitMessage}" https://api.newrelic.com/deployments.xml || _exit $?
_exit 0
