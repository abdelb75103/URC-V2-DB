import process from 'node:process';

import { hashTeamPassword } from '../lib/team-session.ts';

if (process.argv.length !== 2 || process.stdin.isTTY) {
  console.error('Pipe one password on stdin; command-line arguments are not accepted.');
  process.exit(1);
}

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const password = Buffer.concat(chunks).toString('utf8').replace(/\r?\n$/, '');

try {
  process.stdout.write(`${await hashTeamPassword(password)}\n`);
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Unable to hash password.');
  process.exit(1);
}
