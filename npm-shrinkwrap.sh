#!/bin/sh
git checkout master || exit $?

### Remove old npm-shrinkwrap.json
rm -f npm-shrinkwrap.json || exit $?

### Run tests. (This is supposed to do new npm install)
npm run teamcity --silent || exit $?

### Deploy new npm-shrinkwrap.json
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