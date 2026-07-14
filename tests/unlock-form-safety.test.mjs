import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('unlock form native fallback posts without putting the password in the URL', async () => {
  const source = await readFile(new URL('../components/unlock-form.tsx', import.meta.url), 'utf8');

  assert.match(
    source,
    /<form\s+action="\/api\/team-session\/unlock"\s+method="post"\s+onSubmit=\{onSubmit\}>/
  );
});
