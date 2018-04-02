// Usage
// author=$(node ./getSlackUser.js)
// or
// author=$(curl –silent -L 'https://raw.githubusercontent.com/debitoor/teamcity-merge/master/getSlackUser.js' | node)

const { execSync } = require('child_process');
const assert = require('assert');

assert(process.env.SLACK_TOKEN, 'process.env.SLACK_TOKEN should be specified');

//Map of emails -> slack user name
const emailsMap = {
	'eagleeyes91@gmail.com': 'eagleeye',
	'bogdan.bele@yahoo.com': 'bogdan',
	'anton.mamant@gmail.com': 'mamant',
	'mpush@inbox.ru': 'mpushkin',
	'jp@jonatanpedersen.com': 'jonatanpedersen',
	'kollner@gmail.com': 'kollner',
	'hiller@live.dk': 'hilleer',
	'alexeymalyarov@gmail.com': 'lex',
	'mfbeast@mail.ru': 'mpushkin',
	'niklasgundlev@gmail.com': 'niklas',
	'dgulkovskiy@gmail.com': 'dima',
	'zygimantas.butas@gmail.com': 'zygi',
	'stepan.te.ua@gmail.com': 'stepan'
};

const email = execSync('git log --pretty=format:\'%ae\' -n 1', {encoding: 'utf-8'});
if (email === 'debitoor-bot@debitoor.com') {
	console.log('TeamCity');
	process.exit(0);
}
const usersJSON = execSync(`curl -X POST "https://slack.com/api/users.list?token=${process.env.SLACK_TOKEN}" -s`);
const users = JSON.parse(usersJSON);
const slackUser = emailsMap[email];

const user = users.members.find((m) =>
	m.name === slackUser || m.profile.email === email
);
if(!user) {
	console.log(`${slackUser}|${email} (could not find this slack-username or email in slack?! Fix it here: https://github.com/debitoor/teamcity-merge/blob/master/getSlackUser.js)`);
	process.exit(0);
}
console.log(`<@${user.id}|${slackUser}>`);
