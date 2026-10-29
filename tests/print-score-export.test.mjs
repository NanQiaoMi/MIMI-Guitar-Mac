import assert from 'node:assert/strict';
import test from 'node:test';
import { savePdfPages } from '../src/lib/printScore.ts';

function recordingPdf() {
  const calls = { addPage: 0, addImage: [], save: [] };
  return {
    calls,
    document: {
      addPage() { calls.addPage++; },
      addImage(...args) { calls.addImage.push(args); },
      save(filename) { calls.save.push(filename); },
    },
  };
}

test('PDF encoding failure rejects and never saves a blank or partial document', async () => {
  const recorder = recordingPdf();
  let rasterized = 0;
  await assert.rejects(
    savePdfPages(
      ['<svg>first</svg>', '<svg>unencodable</svg>'],
      'score.pdf',
      () => recorder.document,
      async () => {
        rasterized++;
        return rasterized === 1 ? { imgData: 'data:image/jpeg;base64,valid', width: 794, height: 1123 } : null;
      },
      async () => {},
    ),
    /第 2 页的谱面图像编码失败，未保存 PDF/,
  );
  assert.equal(rasterized, 2);
  assert.equal(recorder.calls.addPage, 0);
  assert.equal(recorder.calls.addImage.length, 1);
  assert.deepEqual(recorder.calls.save, []);
});

test('PDF saves only after every rendered page has a valid JPEG payload', async () => {
  const recorder = recordingPdf();
  const images = ['data:image/jpeg;base64,page-1', 'data:image/jpeg;base64,page-2'];
  await savePdfPages(
    ['<svg>page 1</svg>', '<svg>page 2</svg>'],
    'score.pdf',
    () => recorder.document,
    async () => ({ imgData: images.shift(), width: 794, height: 1123 }),
    async () => {},
  );

  assert.equal(recorder.calls.addPage, 1);
  assert.equal(recorder.calls.addImage.length, 2);
  assert.deepEqual(recorder.calls.save, ['score.pdf']);
});

test('PDF with no rendered pages refuses to create or save a document', async () => {
  let created = false;
  await assert.rejects(
    savePdfPages([], 'empty.pdf', () => { created = true; return recordingPdf().document; }),
    /没有生成可打印的谱面页面，未保存 PDF/,
  );
  assert.equal(created, false);
});
