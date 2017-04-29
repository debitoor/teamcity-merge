const fs = require('fs');
const path = require('path');
let log = fs.readFileSync(path.join(__dirname, 'err.log'), 'utf-8')
	.split('\n')
	.filter(line => !/^npm (ERR|WARN)/.test(line))
	.join('')
	.replace(/\|n/g, '\n');
console.log(log);
