import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseGpToIbe } from '../src/lib/gpUpload.ts';
import {
  createApprovedTabAtomically,
  ExistingTabError,
  stageUploadAndCreateRecord,
  validateStoredEditableIbe,
} from '../src/lib/gpUpload.ts';

const canon = new Uint8Array(readFileSync(new URL('./fixtures/canon.gp5', import.meta.url)));
const scoreIbe = parseGpToIbe(canon).ibe;

function memoryFiles(initial = []) {
  const files = new Map(initial.map(([path, bytes]) => [path, Uint8Array.from(bytes)]));
  return {
    files,
    async createExclusiveFile(path, bytes) {
      if (files.has(path)) {
        const error = new Error('already exists');
        error.code = 'EEXIST';
        throw error;
      }
      files.set(path, Uint8Array.from(bytes));
    },
    async removeFile(path) {
      if (!files.has(path)) throw new Error('missing');
      files.delete(path);
    },
  };
}

function uploadInput() {
  return {
    scorePath: '/virtual/storage/upload/abc123.ibe',
    scoreBytes: scoreIbe,
    screenshotPath: '/virtual/storage/screenshots/upload/abc123.png',
    screenshotUrl: '/storage/screenshots/upload/abc123.png',
    recordData: (screenshotUrl) => ({ id: 'abc123', screenshotUrl }),
  };
}

function baseDependencies(memory) {
  return {
    ensureDirectory: async () => {},
    createExclusiveFile: memory.createExclusiveFile,
    removeFile: memory.removeFile,
    renderScreenshot: async (path) => {
      memory.files.set(path, new Uint8Array([1, 2, 3]));
      return true;
    },
    createRecord: async () => ({ id: 'abc123' }),
  };
}

test('数据库记录创建失败时清理本次新建的乐谱和截图', async () => {
  const memory = memoryFiles();
  const dependencies = {
    ...baseDependencies(memory),
    createRecord: async () => { throw new Error('mock database failure'); },
  };

  await assert.rejects(stageUploadAndCreateRecord(uploadInput(), dependencies), /mock database failure/);
  assert.equal(memory.files.size, 0);
});

test('独占创建遇到已有乐谱时拒绝且保留原文件', async () => {
  const existingScore = Uint8Array.from([9, 8, 7]);
  const memory = memoryFiles([[uploadInput().scorePath, existingScore]]);

  await assert.rejects(stageUploadAndCreateRecord(uploadInput(), baseDependencies(memory)), (error) => {
    assert.equal(error.code, 'EEXIST');
    return true;
  });
  assert.deepEqual([...memory.files.get(uploadInput().scorePath)], [...existingScore]);
});

test('截图路径冲突不会覆盖或删除已有截图', async () => {
  const oldScreenshot = Uint8Array.from([4, 5, 6]);
  const memory = memoryFiles([[uploadInput().screenshotPath, oldScreenshot]]);

  const result = await stageUploadAndCreateRecord(uploadInput(), baseDependencies(memory));
  assert.equal(result.screenshotUrl, null);
  assert.deepEqual([...memory.files.get(uploadInput().screenshotPath)], [...oldScreenshot]);
  assert.ok(memory.files.has(uploadInput().scorePath));
});

test('审核前校验存储的 IBE，并在事务内原子创建曲谱与更新上传状态', async () => {
  assert.doesNotThrow(() => validateStoredEditableIbe(scoreIbe));
  assert.throws(() => validateStoredEditableIbe(new Uint8Array([1, 2, 3])), /原始曲谱/);

  const calls = [];
  const fakeTx = {
    tab: {
      async findUnique() { calls.push('find'); return null; },
      async create() { calls.push('create-tab'); },
    },
    uploadRecord: {
      async update() { calls.push('update-upload'); throw new Error('mock update failure'); },
    },
  };
  let transactionEntered = false;
  const transaction = async (work) => {
    transactionEntered = true;
    return work(fakeTx);
  };

  await assert.rejects(createApprovedTabAtomically(transaction, 'abc123', { id: 'abc123' }), /mock update failure/);
  assert.equal(transactionEntered, true);
  assert.deepEqual(calls, ['find', 'create-tab', 'update-upload']);
});

test('已有曲谱由事务内检查拒绝，避免并发重复入库', async () => {
  const transaction = async (work) => work({
    tab: { findUnique: async () => ({ id: 'abc123' }), create: async () => assert.fail('must not create') },
    uploadRecord: { update: async () => assert.fail('must not update') },
  });

  await assert.rejects(createApprovedTabAtomically(transaction, 'abc123', { id: 'abc123' }), ExistingTabError);
});

test('screenshot failure cleans its reserved file without failing score upload', async () => {
  const memory = memoryFiles();
  const dependencies = {
    ...baseDependencies(memory),
    renderScreenshot: async () => { throw new Error('renderer unavailable'); },
  };

  const result = await stageUploadAndCreateRecord(uploadInput(), dependencies);
  assert.equal(result.screenshotUrl, null);
  assert.deepEqual([...memory.files.keys()], [uploadInput().scorePath]);
});