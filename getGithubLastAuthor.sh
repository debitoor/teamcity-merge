#!/usr/bin/env bash
# Usage
# author=$(./getGithubLastAuthor.sh)
# or
# author=$(curl –silent -L 'https://raw.githubusercontent.com/debitoor/teamcity-merge/master/getGithubLastAuthor.sh' | bash)


#Map of emails -> github usernames

declare -A developers

developers["eagleeyes91@gmail.com"]="eagleeye"
developers["a.bubenshchykov@gmail.com"]="bubenshchykov"
developers["evgen.filatov@gmail.com"]="wtfil"
developers["allan@878.dk"]="ebdrup"
developers["anton.mamant@gmail.com"]="mamant"
developers["mpush@inbox.ru"]="mpushkin"
developers["jp@jonatanpedersen.com"]="jonatanpedersen"
developers["ogr@debitoor.com"]="Oligrand";
developers["ssc@debitoor.com"]="sscdebitoor";
developers["kollner@gmail.com"]="kollner";
developers["dra@debitoor.com"]="bifrost";
developers["philip.shurpik@gmail.com"]="philipshurpik"

function getGithubLastAuthor()
{
	author=`git log --pretty=format:'%ae' -n 1`
	githublogin="${developers[$author]}"
	echo $githublogin
}


echo $(getGithubLastAuthor)
