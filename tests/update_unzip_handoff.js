// Exercise the real unzip export with a mocked worker and FiveM scheduler.
// Run with: node tests/update_unzip_handoff.js
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../sonorancms/server/util/unzip.js'), 'utf8');

function scenario({ failConfigSync = false } = {}) {
  const scheduled = [];
  const trace = [];
  const completions = [];
  const registered = {};
  let worker;

  class MockWorker extends EventEmitter {
    constructor() {
      super();
      this.stdout = new EventEmitter();
      this.stderr = new EventEmitter();
    }

    send(message) {
      this.message = message;
    }
  }

  const mockedFs = {
    existsSync(file) {
      trace.push('config exists');
      return file.includes('ace-permissions_config.dist.json');
    },
    renameSync() {
      trace.push('config rename');
      if (failConfigSync) throw new Error('config permission denied');
    },
  };
  const mockedChildProcess = {
    fork(file, args, options) {
      assert(file.endsWith('unzip-child.js'));
      assert.equal(options.windowsHide, true);
      worker = new MockWorker();
      return worker;
    },
  };
  function mockedExports(name, callback) {
    registered[name] = callback;
  }
  mockedExports.sonorancms = {
    unzipCoreCompleted(success, error) {
      trace.push('Lua completion export');
      completions.push({ success, error });
    },
  };
  vm.runInNewContext(source, {
    require(name) {
      if (name === 'child_process') return mockedChildProcess;
      if (name === 'path') return path;
      if (name === 'fs') return mockedFs;
      throw new Error(`Unexpected import: ${name}`);
    },
    exports: mockedExports,
    GetCurrentResourceName: () => 'sonorancms',
    GetResourcePath: () => '/fake/resources/sonorancms',
    setImmediate(callback) {
      scheduled.push(callback);
    },
    console: { log() {}, error(message) { throw new Error(message); } },
  }, { filename: 'unzip.js' });

  return { registered, scheduled, trace, completions, get worker() { return worker; } };
}

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
}

async function run() {
  const success = scenario();
  success.registered.UnzipFile('/fake/update.zip', '/fake/resources', false);
  assert.equal(success.worker.message.file, '/fake/update.zip');
  assert.equal(success.worker.message.dest, '/fake/resources');
  success.worker.emit('message', { ok: true });
  success.worker.emit('exit', 0, null);
  await flushPromises();
  assert.equal(success.scheduled.length, 1, 'Only one game-thread callback should be scheduled');
  assert.deepEqual(success.completions, [], 'Worker completion must not call the Lua export inline');
  assert.deepEqual(success.trace, [], 'Config changes must wait for the game-thread handoff');
  success.scheduled.shift()();
  assert.deepEqual(success.completions, [{ success: true, error: 'nil' }]);
  assert(success.trace.indexOf('config rename') < success.trace.indexOf('Lua completion export'));

  const workerError = scenario();
  workerError.registered.UnzipFile('/fake/update.zip', '/fake/resources', false);
  workerError.worker.emit('message', { ok: false, error: 'bad archive' });
  await flushPromises();
  assert.deepEqual(workerError.completions, []);
  assert.equal(workerError.scheduled.length, 1);
  workerError.scheduled.shift()();
  assert.deepEqual(workerError.completions, [{ success: false, error: 'bad archive' }]);
  assert.deepEqual(workerError.trace, ['Lua completion export'], 'Do not touch configs after extraction failure');

  const configError = scenario({ failConfigSync: true });
  configError.registered.UnzipFile('/fake/update.zip', '/fake/resources', false);
  configError.worker.emit('message', { ok: true });
  await flushPromises();
  assert.equal(configError.scheduled.length, 1);
  configError.scheduled.shift()();
  assert.deepEqual(configError.completions, [{ success: false, error: 'config permission denied' }]);

  console.log('unzip handoff: worker completion, game-thread scheduling, and errors passed');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
