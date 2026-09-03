import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const read = (file) => readFile(new URL(`../${file}`, import.meta.url), 'utf8');

test('the preview reuses one generated PDF for display and download', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.equal(preview.match(/\.toBlob\(\)/g)?.length, 1);
  assert.equal(preview.match(/URL\.createObjectURL/g)?.length, 1);
  assert.match(preview, /<Document file=\{currentPdf\.url\}/);
  assert.match(preview, /link\.href = currentPdf\.url/);
  assert.match(preview, /link\.download = downloadFileName/);
  assert.doesNotMatch(preview, /window\.print|print\(\)/);
  assert.match(preview, /if \(!sections\.length\) return/);
  assert.match(preview, /disabled=\{!currentPdf \|\| loadingPreview\}/);
  assert.match(preview, /renderedPdf\?\.key === generationKey/);
  assert.match(preview, /loadedPreview\?\.key === generationKey/);
  assert.match(preview, /generationQueueRef\.current = generationQueueRef\.current\.then/);
  assert.match(preview, /window\.setTimeout\([\s\S]*?, 150\)/);
  assert.match(preview, /requestAnimationFrame\(\(\) => \{ if \(generationKeyRef\.current === generationKey\) onPreviewReady\?\.\(\); \}\)/);
});

test('the PDF page scales to the available preview width', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.match(preview, /new ResizeObserver\(updateWidth\)/);
  assert.match(preview, /Math\.min\(595, Math\.max\(240, frame\.clientWidth - 16\)\)/);
  assert.match(preview, /<Page[\s\S]*?width=\{previewWidth\}/);
});

test('the preview renders every PDF page in one continuous scroll area', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.match(preview, /max-h-\[calc\(100vh-12rem\)\][^\"]*overflow-y-auto/);
  assert.match(preview, /reportPreviewPages\(sections\)\.slice\(0, pageCount\)/);
  assert.match(preview, /className="relative max-w-full"[\s\S]*?<Page[\s\S]*?renderPageAction\(page\)/);
  assert.doesNotMatch(preview, /reportPreviewPages\(sections\)\.map/);
  assert.doesNotMatch(preview, /ChevronLeft|ChevronRight|Preview page controls/);
});

test('the preview exposes accessible updating and empty states', async () => {
  const preview = await read('components/report/report-preview.tsx');

  assert.match(preview, /role="status" aria-live="polite" aria-atomic="true"/);
  assert.match(preview, /role="region" tabIndex=\{0\} aria-label="Scrollable PDF report pages" aria-busy=\{generating \|\| loadingPreview\}/);
  assert.match(preview, /aria-describedby="report-preview-status"/);
  assert.match(preview, /No report sections selected/);
  assert.match(preview, /No sections selected\. Restore a section/);
  assert.doesNotMatch(preview, /pageCount\}-page|sections\.length\}-page/);
  assert.match(preview, /TextLayer\.css/);
  assert.doesNotMatch(preview, /renderTextLayer=\{false\}/);
  assert.doesNotMatch(preview, /<section[^>]*aria-busy/);
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
