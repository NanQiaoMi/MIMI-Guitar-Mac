import assert from 'node:assert/strict';
import test, { afterEach, beforeEach } from 'node:test';
import { createRequire } from 'node:module';
import { createEmptyPersonalData, validatePersonalData } from '../src/lib/personal/validation.ts';
import { exportPersonalBackup, previewBackup, restoreBackup } from '../src/lib/personal/backup.ts';
import { mutatePersonalData, readPersonalData } from '../src/lib/personal/repository.ts';

const { IDBFactory } = createRequire(import.meta.url)('fake-indexeddb');
const previous = {};
beforeEach(() => {
  for (const key of ['window', 'indexedDB', 'localStorage']) previous[key] = globalThis[key];
  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  const values = new Map();
  globalThis.localStorage = {
    get length() { return values.size; }, key: (index) => [...values.keys()][index] ?? null,
    getItem: (key) => values.get(key) ?? null, setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
});
afterEach(() => {
  for (const key of Object.keys(previous)) {
    if (previous[key] === undefined) delete globalThis[key];
    else globalThis[key] = previous[key];
  }
});

function fixture() {
  const data = createEmptyPersonalData();
  data.migrationCompleted = true;
  data.scores.push({ id: 'catalog:capo', source: 'catalog', sourceId: 'capo', revision: 'r1', title: 'Capo fixture', artist: '', category: 'guitar', format: 'ibe', scoreUrl: '/storage/capo.ibe', createdAt: 1, updatedAt: 1 });
  data.resumes.push({ scoreId: 'catalog:capo', scoreRevision: 'r1', tick: 960, timeMs: 500, speed: 120, capo: 0, transpose: 0, loop: null, trackIndexes: [0], metronome: false, countIn: false, updatedAt: 2 });
  return data;
}

test('legacy numeric capo remains optional-source compatible and explicit source flag is strictly boolean', () => {
  const data = fixture();
  validatePersonalData(data);
  assert.equal(data.resumes[0].useSourceCapo, undefined);
  for (const flag of [true, false]) {
    data.resumes[0].useSourceCapo = flag;
    validatePersonalData(data);
  }
  for (const invalid of [null, 'true', 1]) {
    data.resumes[0].useSourceCapo = invalid;
    assert.throws(() => validatePersonalData(data), /useSourceCapo/);
  }
});

test('existing half-step-down control can persist while impossible capo positions are rejected', () => {
  const data = fixture();
  for (const capo of [-1, 0, 6, 24]) {
    data.resumes[0].capo = capo;
    validatePersonalData(data);
  }
  for (const capo of [-2, 1.5, 25, Number.NaN]) {
    data.resumes[0].capo = capo;
    assert.throws(() => validatePersonalData(data), /capo/);
  }
});

test('backup and restore retain source-capo mode and zero-volume track mix without rewriting legacy records', async () => {
  const data = fixture();
  data.resumes[0].useSourceCapo = true;
  data.resumes[0].trackMix = [{ index: 0, muted: false, soloed: false, volume: 0, program: 24 }];
  await mutatePersonalData((draft) => Object.assign(draft, data));
  const backup = await exportPersonalBackup();
  const preview = await previewBackup(backup);
  assert.equal(preview.data.resumes[0].useSourceCapo, true);
  assert.equal(preview.data.resumes[0].trackMix[0].volume, 0);
  const restored = await restoreBackup(preview, preview.expectedRevision);
  assert.equal(restored.resumes[0].useSourceCapo, true);
  assert.equal((await readPersonalData()).resumes[0].trackMix[0].volume, 0);
});
