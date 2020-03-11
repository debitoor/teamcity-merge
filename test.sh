#!/bin/sh
stepName=""
step_end(){
	echo "##teamcity[progressFinish '${stepName}']"
}
step_start(){
	if [ "${stepName}" != '' ]
	then
		step_end
	fi
	stepName=`echo "${1}" | sed -e 's/ /_/g'`
	echo "##teamcity[progressStart '${stepName}']"
}

step_start "test number 1"
step_start "test number 2"
step_end