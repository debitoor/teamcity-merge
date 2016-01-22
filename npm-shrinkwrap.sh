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



step_start "Checkout master branch"
git checkout master || exit $?

step_start "Remove old npm-shrinkwrap.json"
rm -f npm-shrinkwrap.json || exit $?

step_start "Run tests with npm run teamcity. (This is supposed to do new npm install)"
npm run teamcity --silent || exit $?

step_start "Run nightly-tests if they exist"
nightlyTests=`cat package.json | jsonfilter "scripts.nightly-test"`
if [ "${nightlyTests}" != '' ]
	echo "Running noightly-tests:${nightlyTests}."
	npm run nightly-test --silent || exit $?
then
	echo "No npm script called nightly-test found"
fi

step_start "Deploy new npm-shrinkwrap.json"
datetime=`date +%%Y-%%m-%%d_%%H-%%M-%%S`
branch=`echo "update_npm-shrinkwrap.json_${datetime}"`
git checkout -b "${branch}" || exit $?
git config user.email "debitoor-bot@debitoor.com" || exit $?
git config user.name "Teamcity" || exit $?
npm shrinkwrap --dev || exit $?
git add npm-shrinkwrap.json || exit $?
git commit -m "update npm-shrinkwrap.json" || exit 0 ### If there are no changes we just exit
git push origin "${branch}:ready/${branch}_no_pull_request" || exit $?
git checkout master || exit $?
git branch -D "${branch}"

step_end