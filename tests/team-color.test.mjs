import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function loadModule(relativePath) {
  const source = await readFile(new URL(relativePath, import.meta.url), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

const teamColor = await loadModule('../lib/team-color.ts');
const teamsSource = await readFile(new URL('../config/teams.ts', import.meta.url), 'utf8');

const clubs = [...teamsSource.matchAll(
  /id: '([a-z-]+)'.*?accent: '(#[0-9A-Fa-f]{6})', accentSecondary: '(#[0-9A-Fa-f]{6})'/g,
)].map(([, id, accent, accentSecondary]) => ({ id, accent, accentSecondary }));

const surfaces = ['background', 'card', 'muted'];

test('every club accent is read from config/teams.ts', () => {
  assert.equal(clubs.length, 16);
});

test('each club clears the target on the surface it was resolved against', () => {
  const { contrastRatio, hexToRgb, resolveTeamColor, surfaceHex, CONTRAST_TARGET } = teamColor;
  for (const club of clubs) {
    for (const surface of surfaces) {
      const backdrop = surfaceHex(surface);
      const { color } = resolveTeamColor({ ...club, backdrop });
      const ratio = contrastRatio(hexToRgb(color), hexToRgb(backdrop));
      assert.ok(
        ratio >= CONTRAST_TARGET - 1e-6,
        `${club.id} on ${surface}: ${color} is ${ratio.toFixed(2)}:1`,
      );
    }
  }
});

test('the muted-resolved mark clears the target on background, card and muted', () => {
  const { contrastRatio, hexToRgb, resolveTeamPalette, surfaceHex, CONTRAST_TARGET } = teamColor;
  for (const club of clubs) {
    const { primary, mark } = resolveTeamPalette(club);
    assert.equal(primary, mark);
    for (const surface of surfaces) {
      const ratio = contrastRatio(hexToRgb(mark), hexToRgb(surfaceHex(surface)));
      assert.ok(
        ratio >= CONTRAST_TARGET - 1e-6,
        `${club.id} mark on ${surface}: ${mark} is ${ratio.toFixed(2)}:1`,
      );
    }
  }
});

test('the h1 text colour clears the target on the page background', () => {
  const { contrastRatio, hexToRgb, resolveTeamPalette, surfaceHex, CONTRAST_TARGET } = teamColor;
  for (const club of clubs) {
    const ratio = contrastRatio(hexToRgb(resolveTeamPalette(club).text), hexToRgb(surfaceHex('background')));
    assert.ok(ratio >= CONTRAST_TARGET - 1e-6, `${club.id} text: ${ratio.toFixed(2)}:1`);
  }
});

test('a passing accent is returned unchanged and a chromatic accent keeps its hue', () => {
  const { resolveTeamColor, rgbToOklch, hexToRgb, surfaceHex } = teamColor;
  const backdrop = surfaceHex('muted');
  for (const club of clubs) {
    const { color, source } = resolveTeamColor({ ...club, backdrop });
    const accentHue = rgbToOklch(hexToRgb(club.accent));
    if (source === 'accent') {
      assert.equal(color.toLowerCase(), club.accent.toLowerCase(), `${club.id} should be untouched`);
      continue;
    }
    if (source !== 'lightened') continue;
    const resolvedHue = rgbToOklch(hexToRgb(color));
    const delta = Math.abs(((resolvedHue.h - accentHue.h + 540) % 360) - 180);
    assert.ok(delta < 1, `${club.id} hue drifted by ${delta.toFixed(2)} degrees`);
    assert.ok(resolvedHue.l > accentHue.l, `${club.id} should have been lightened`);
  }
});

test('a wholly achromatic club resolves to white, and a chromatic secondary still wins', () => {
  const { resolveTeamColor, surfaceHex, contrastRatio, hexToRgb } = teamColor;
  // Ospreys and Sharks: #000000 on #FFFFFF, no chromatic identity anywhere in
  // their config. White is their real second colour (decision, 2026-07-25).
  const black = resolveTeamColor({
    accent: '#000000',
    accentSecondary: '#FFFFFF',
    backdrop: surfaceHex('muted'),
  });
  assert.equal(black.source, 'achromatic');
  assert.equal(black.color.toLowerCase(), '#ffffff');
  for (const surface of ['background', 'card', 'muted']) {
    const ratio = contrastRatio(hexToRgb(black.color), hexToRgb(surfaceHex(surface)));
    assert.ok(ratio >= 3, `white fell below 3:1 on ${surface} at ${ratio.toFixed(2)}`);
  }

  const chromaticSecondary = resolveTeamColor({
    accent: '#000000',
    accentSecondary: '#E87722',
    backdrop: surfaceHex('muted'),
  });
  assert.equal(chromaticSecondary.source, 'secondary');
});

test('the resolver is pure: repeated calls return the same colour', () => {
  const { resolveTeamColor, surfaceHex } = teamColor;
  const input = { accent: '#D2232A', accentSecondary: '#FFFFFF', backdrop: surfaceHex('card') };
  assert.deepEqual(resolveTeamColor(input), resolveTeamColor({ ...input }));
});

test('the palette reports how the colour was reached so text call sites can opt out', () => {
  const { resolveTeamPalette } = teamColor;
  const byId = Object.fromEntries(clubs.map((club) => [club.id, resolveTeamPalette(club)]));
  assert.equal(byId.ospreys.source, 'achromatic');
  assert.equal(byId.sharks.source, 'achromatic');
  assert.equal(byId.munster.source, 'lightened');
  assert.equal(byId.edinburgh.source, 'lightened');
  assert.equal(byId.zebre.source, 'accent');
});
