import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const read = (file) => readFile(new URL(`../${file}`, import.meta.url), 'utf8');

test('the preview reuses one generated PDF for display and download', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.equal(preview.match(/\.toBlob\(\)/g)?.length, 1);
  assert.equal(preview.match(/URL\.createObjectURL/g)?.length, 1);
  assert.match(preview, /<Document file=\{blobUrl\}/);
  assert.match(preview, /link\.href = blobUrl/);
  assert.match(preview, /link\.download = downloadFileName/);
  assert.doesNotMatch(preview, /window\.print|print\(\)/);
});

test('the PDF page scales to the available preview width', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.match(preview, /new ResizeObserver\(updateWidth\)/);
  assert.match(preview, /Math\.min\(595, Math\.max\(240, frame\.clientWidth - 16\)\)/);
  assert.match(preview, /<Page[\s\S]*?width=\{previewWidth\}/);
});

test('the preview renders every PDF page in one continuous scroll area', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.match(preview, /max-h-\[calc\(100vh-12rem\)\] overflow-y-auto/);
  assert.match(preview, /Array\.from\(\{ length: pageCount \}/);
  assert.doesNotMatch(preview, /ChevronLeft|ChevronRight|Preview page controls/);
});

test('production report modules do not import fixture or preview data', async () => {
  const production = await Promise.all([
    'lib/report-model.ts',
    'lib/report-comparison.ts',
    'components/report/report-document.tsx',
    'components/report/report-preview.tsx',
  ].map(read));
  const source = production.join('\n');

  assert.doesNotMatch(source, /content\/reporting|report-fixtures|DashboardSupplement|ExposureReviewPreview/);
});
