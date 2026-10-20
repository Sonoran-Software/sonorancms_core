// Run with: node tests/whitelist_backup.js
// Load the real helper and module with virtual disk/API/timers; never contact CMS or FiveM.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const helperSource = fs.readFileSync(path.join(root, 'sonorancms/server/util/sonoran.js'), 'utf8');
const moduleSource = fs.readFileSync(path.join(root, 'sonorancms/server/modules/whitelist/whitelist_sv.js'), 'utf8');
const directory = 'server/modules/whitelist/';
const resourcePath = path.join('C:', 'fake', 'resources', 'sonorancms');
const backupPath = path.join(resourcePath, directory, 'whitelist_backup.json');
const context = { communityId: 'community-A', serverId: '17', apiIdType: 'discord', apiUrl: 'https://cms.invalid/' };
const plain = (value) => JSON.parse(JSON.stringify(value));
const snapshot = (enabled, ...ids) => ({ enabled, players: ids.map((id) => ({ apiIds: Array.isArray(id) ? id : [id] })) });
const saved = (overrides = {}) => ({ version: 1, ...context, enabled: true,
  updatedAt: '2026-10-20T00:00:00.000Z', apiIds: ['member'], ...overrides });

async function flush() {
  // Promise continuations cross the VM boundary and the module's refresh finally handler.
  for (let index = 0; index < 12; index++) await Promise.resolve();
}

async function scenario({ cache, files = new Map(), module = true, enabled = true } = {}) {
  if (cache !== undefined) files.set(backupPath, typeof cache === 'string' ? cache : JSON.stringify(cache));
  const timers = new Map();
  const requests = [];
  const events = new Map();
  const netEvents = [];
  const writes = [];
  const logs = [];
  const drops = [];
  const players = new Map();
  const failures = { write: false, rename: false, request: false };
  let now = 0;
  let timerId = 0;
  let schedulerTicks = 0;
  const epoch = Date.parse('2026-10-20T00:00:00.000Z');
  class FakeDate extends Date {
    constructor(...args) { super(...(args.length ? args : [epoch + now])); }
    static now() { return epoch + now; }
  }
  const schedule = (callback, delay = 0, interval = 0) => {
    const id = ++timerId;
    timers.set(id, { callback, at: now + delay, interval });
    return id;
  };
  const registered = Object.assign((name, callback) => { registered.sonorancms[name] = callback; }, {
    sonorancms: {
      getWhitelistContext() {
        if (module) assert(schedulerTicks > 0, 'Cross-runtime context must wait for the first scheduler tick');
        return { ...context };
      },
      getAppropriateIdentifier: (source) => players.get(source)?.id ?? 'NOT FOUND',
      jsGetPlayers: () => [...players.keys()],
      sleep: (delay) => new Promise((resolve) => schedule(resolve, delay)),
      performApiRequest(data, type, callback) {
        if (failures.request) throw new Error('request failed');
        requests.push({ data: plain(data), type, callback, responded: false });
      },
    },
  });
  const sandbox = {
    exports: registered,
    Date: FakeDate,
    require(name) {
      if (name === 'path') return path;
      if (name === 'fs') return {
        writeFileSync(file, contents) {
          writes.push({ operation: 'write', file });
          if (failures.write) throw new Error('write denied');
          files.set(file, contents);
        },
        renameSync(from, to) {
          writes.push({ operation: 'rename', from, to });
          if (failures.rename) throw new Error('rename denied');
          assert(files.has(from), 'The temporary file must exist before rename');
          files.set(to, files.get(from));
          files.delete(from);
        },
      };
      throw new Error(`Unexpected import: ${name}`);
    },
    GetCurrentResourceName: () => 'sonorancms',
    GetResourcePath: () => resourcePath,
    GetPlayerName: (source) => players.get(source)?.name,
    DropPlayer: (source, reason) => drops.push({ source, reason }),
    LoadResourceFile(resource, file) {
      if (file.endsWith('whitelist_config.json')) return JSON.stringify({ enabled });
      return files.get(path.join(resourcePath, file)) ?? null;
    },
    on: (event, callback) => events.set(event, callback),
    onNet: (event) => netEvents.push(event),
    RegisterNetEvent: (event) => netEvents.push(event),
    setTimeout: (callback, delay) => schedule(callback, delay),
    clearTimeout: (id) => timers.delete(id),
    setInterval: (callback, delay) => schedule(callback, delay, delay),
    console: { log: (message) => logs.push(message) },
    source: 0,
  };
  const runtime = vm.createContext(sandbox);
  vm.runInContext(helperSource, runtime, { filename: 'sonoran.js' });
  if (module) vm.runInContext(moduleSource, runtime, { filename: 'whitelist_sv.js' });

  const result = {
    api: registered.sonorancms, requests, events, netEvents, writes, files, logs, drops, players, failures,
    disk: () => files.has(backupPath) ? JSON.parse(files.get(backupPath)) : null,
    pending(type) {
      const request = requests.find((item) => item.type === type && !item.responded);
      assert(request, `Expected a pending ${type} request`);
      return request;
    },
    async respond(type, result, ok = true) {
      await flush();
      const request = this.pending(type);
      request.responded = true;
      request.callback(result, ok);
      await flush();
      return request;
    },
    async advance(milliseconds) {
      const target = now + milliseconds;
      let iterations = 0;
      while (true) {
        const next = [...timers.entries()].filter(([, timer]) => timer.at <= target)
          .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
        if (!next) break;
        assert(++iterations < 1000, 'Fake timer loop must terminate');
        const [id, timer] = next;
        now = timer.at;
        if (timer.interval) timer.at += timer.interval; else timers.delete(id);
        schedulerTicks++;
        timer.callback();
        await flush();
      }
      now = target;
      await flush();
    },
    async join(id = 'member', source = 10) {
      players.set(source, { id, name: `Player ${source}` });
      sandbox.source = source;
      const done = [];
      const steps = [];
      const promise = events.get('playerConnecting')(`Player ${source}`, () => {}, {
        defer: () => steps.push('defer'),
        update: () => steps.push('update'),
        done: (reason) => { steps.push('done'); done.push(reason); },
      });
      await this.advance(0);
      return { done, steps, promise };
    },
    async finish(join) {
      await this.advance(0);
      await join.promise;
      assert.equal(join.done.length, 1, 'Every join must finish exactly once');
      assert.deepEqual(join.steps, ['defer', 'update', 'done']);
      return join.done[0];
    },
    rankUpdate: () => events.get('sonoran_whitelist::rankupdate')(),
  };
  await result.advance(0);
  return result;
}

async function helperChecks() {
  const s = await scenario({ module: false });
  const results = [];
  s.api.getFullWhitelist((result) => results.push(plain(result)), true);
  assert.deepEqual(s.pending('FULL_WHITELIST').data, { serverId: '17', snapshot: true });
  await s.respond('FULL_WHITELIST', JSON.stringify(snapshot(false)));
  assert.deepEqual(results.pop(), { success: true, data: [], enabled: false });

  s.api.getFullWhitelist((result) => results.push(plain(result)));
  assert.equal(s.pending('FULL_WHITELIST').data.snapshot, false);
  await s.respond('FULL_WHITELIST', [{ apiIds: ['legacy-client'] }]);
  assert.deepEqual(results.pop(), { success: true, data: [{ apiIds: ['legacy-client'] }] });

  for (const invalid of [null, 'not json', [], {}, { enabled: true, players: null },
    { players: [] }, { enabled: true, players: [{ apiIds: [''] }] },
    { enabled: true, players: [{ apiIds: [5] }] }]) {
    s.api.getFullWhitelist((result) => results.push(plain(result)), true);
    await s.respond('FULL_WHITELIST', invalid);
    assert.equal(results.pop().backendError, true, 'Malformed successes must be treated as an outage');
  }

  s.api.checkCMSWhitelist('member', (result) => results.push(plain(result)));
  assert.deepEqual(s.pending('VERIFY_WHITELIST').data, { apiId: 'member', serverId: '17' });
  const timedOut = s.pending('VERIFY_WHITELIST');
  await s.advance(10000);
  assert.equal(results.length, 1);
  assert.equal(results[0].backendError, true);
  timedOut.responded = true;
  timedOut.callback('Whitelisted', true);
  assert.equal(results.length, 1, 'A late API callback must not complete twice');
  results.length = 0;

  s.api.getFullWhitelist((result) => results.push(plain(result)), true);
  const missingSnapshotCallback = s.pending('FULL_WHITELIST');
  await s.advance(10000);
  assert.equal(results.length, 1);
  assert.equal(results[0].backendError, true);
  missingSnapshotCallback.responded = true;
  missingSnapshotCallback.callback(snapshot(false), true);
  assert.equal(results.length, 1, 'A late full-list callback must not revive a timed-out request');
  results.length = 0;

  for (const [response, denied, backendError] of [
    ['NOT ALLOWED ON WHITELIST', true, false],
    [JSON.stringify({ message: 'BLOCKED FOR WHITELIST' }), true, false],
    ['INVALID_SERVER_ID', false, false],
    ['SERVER_CONFIG_ERROR', false, false],
    ['HTTP 503', false, true],
  ]) {
    s.api.checkCMSWhitelist('member', (result) => results.push(plain(result)));
    await s.respond('VERIFY_WHITELIST', response, false);
    assert.deepEqual({ denied: results[0].denied, backendError: results[0].backendError }, { denied, backendError });
    results.length = 0;
  }
  s.failures.request = true;
  s.api.checkCMSWhitelist('member', (result) => results.push(plain(result)));
  assert.equal(results.length, 1);
  assert.equal(results[0].backendError, true, 'Thrown requests must still call back');
}

async function snapshotChecks() {
  const s = await scenario();
  assert.equal(s.files.has(backupPath), false, 'Startup must not replace a missing backup with an empty list');
  assert.deepEqual(s.pending('FULL_WHITELIST').data, { serverId: '17', snapshot: true });
  await s.respond('FULL_WHITELIST', snapshot(true, ['member', 'member'], ['second', 'member']));
  assert.deepEqual(s.disk().apiIds, ['member', 'second']);
  assert.equal(s.disk().enabled, true);
  assert.deepEqual(s.writes, [
    { operation: 'write', file: backupPath + '.tmp' },
    { operation: 'rename', from: backupPath + '.tmp', to: backupPath },
  ]);
  const goodDisk = s.files.get(backupPath);
  const restarted = await scenario({ files: s.files });
  assert.equal(restarted.files.get(backupPath), goodDisk, 'Restart must preserve the last good disk cache');
  assert.equal(restarted.writes.length, 0);
  await restarted.respond('FULL_WHITELIST', 'backend down', false);
  const cachedJoin = await restarted.join('second');
  await restarted.respond('VERIFY_WHITELIST', 'backend down', false);
  assert.equal(await restarted.finish(cachedJoin), undefined, 'Valid cached membership must admit during an outage');
  const unknownJoin = await restarted.join('unknown');
  await restarted.respond('VERIFY_WHITELIST', 'backend down', false);
  assert.match(await restarted.finish(unknownJoin), /not in this server's saved whitelist/);

  for (const invalid of [{ enabled: true, players: [{ apiIds: [null] }] }, [], 'invalid']) {
    await s.advance(5 * 60 * 1000);
    await s.respond('FULL_WHITELIST', invalid);
    assert.equal(s.files.get(backupPath), goodDisk, 'Malformed snapshots must leave the previous disk cache intact');
  }
  await s.advance(5 * 60 * 1000);
  await s.respond('FULL_WHITELIST', 'offline', false);
  assert.equal(s.files.get(backupPath), goodDisk);
  await s.advance(5 * 60 * 1000);
  await s.respond('FULL_WHITELIST', JSON.stringify(snapshot(true, 'restored-member')));
  assert.deepEqual(s.disk().apiIds, ['restored-member'], 'The forced periodic refresh must recover after a CMS outage');
  const restored = await s.join('restored-member');
  await s.respond('VERIFY_WHITELIST', 'offline', false);
  assert.equal(await s.finish(restored), undefined, 'A recovered snapshot must become the active offline backup');
  assert.deepEqual(s.netEvents, [], 'Whitelist rank updates must never be registered as a client-triggerable network event');
}

async function invalidCacheChecks() {
  const cases = [undefined, '{ broken JSON', { whitelisted: ['member'] }, saved({ version: 0 }),
    saved({ communityId: 'other' }), saved({ serverId: '18' }), saved({ apiIdType: 'license' }),
    saved({ apiUrl: 'https://other.invalid/' }), saved({ updatedAt: 'invalid' }),
    saved({ enabled: undefined }), saved({ apiIds: [null] })];
  for (const cache of cases) {
    const s = await scenario({ cache });
    const original = s.files.get(backupPath);
    await s.respond('FULL_WHITELIST', 'offline', false);
    const join = await s.join('member');
    await s.respond('VERIFY_WHITELIST', 'offline', false);
    assert.match(await s.finish(join), /no valid whitelist backup/);
    assert.equal(s.files.get(backupPath), original, 'Rejected cache files must not be destroyed on startup or an outage');
  }
}

async function modeAndDecisionChecks() {
  const empty = await scenario();
  await empty.respond('FULL_WHITELIST', snapshot(true));
  assert.equal(empty.disk().enabled, true, 'An empty enabled whitelist must not mean disabled');
  const unknown = await empty.join('unknown');
  await empty.respond('VERIFY_WHITELIST', 'offline', false);
  assert.match(await empty.finish(unknown), /not in this server's saved whitelist/);
  const missing = await empty.join(null);
  assert.match(await empty.finish(missing), /discord identifier is required/);
  await empty.advance(30000);
  const recentlyDisabled = await empty.join(null);
  await empty.respond('FULL_WHITELIST', snapshot(false));
  assert.equal(await empty.finish(recentlyDisabled), undefined,
    'After the join refresh cooldown, disabling whitelist must also stop requiring a player identifier');
  assert.equal(empty.disk().enabled, false);

  const disabled = await scenario();
  await disabled.respond('FULL_WHITELIST', snapshot(false));
  assert.equal(disabled.disk().enabled, false);
  const noIdentifier = await disabled.join(null);
  assert.equal(await disabled.finish(noIdentifier), undefined, 'Explicit disabled mode must also allow players without an identifier');
  assert.equal(disabled.requests.filter((request) => request.type === 'FULL_WHITELIST').length, 1,
    'A fresh disabled snapshot must admit immediately without another snapshot request');
  assert.equal(disabled.requests.some((request) => request.type === 'VERIFY_WHITELIST'), false);

  // Refresh cached disabled mode before joining, so a new online denial can revoke it.
  await disabled.advance(30000);
  const reenabled = await disabled.join('revoked');
  await disabled.respond('FULL_WHITELIST', snapshot(true, 'revoked'));
  await disabled.respond('VERIFY_WHITELIST', 'BLOCKED FOR WHITELIST', false);
  assert.match(await disabled.finish(reenabled), /BLOCKED FOR WHITELIST/);
  assert.equal(disabled.disk().enabled, true);
  assert.deepEqual(disabled.disk().apiIds, []);

  const decisions = await scenario({ cache: saved({ apiIds: ['revoked'] }) });
  const denied = await decisions.join('revoked');
  await decisions.respond('VERIFY_WHITELIST', 'NOT ALLOWED ON WHITELIST', false);
  assert.match(await decisions.finish(denied), /NOT ALLOWED ON WHITELIST/);
  assert.deepEqual(decisions.disk().apiIds, [], 'A live denial must remove saved membership');
  // The older startup snapshot must not undo an individual decision made while it was in flight.
  await decisions.respond('FULL_WHITELIST', snapshot(true, 'revoked'));
  assert.deepEqual(decisions.disk().apiIds, []);
  const allowed = await decisions.join('new-member');
  await decisions.respond('VERIFY_WHITELIST', 'Whitelisted');
  assert.equal(await decisions.finish(allowed), undefined);
  assert.deepEqual(decisions.disk().apiIds, ['new-member']);
  const configFailure = await decisions.join('new-member');
  await decisions.respond('VERIFY_WHITELIST', 'INVALID_SERVER_ID', false);
  assert.match(await decisions.finish(configFailure), /INVALID_SERVER_ID/);
  assert.deepEqual(decisions.disk().apiIds, ['new-member'], 'A server configuration error must not erase valid membership');
  const restart = await scenario({ files: decisions.files });
  await restart.respond('FULL_WHITELIST', 'offline', false);
  for (const [id, shouldAllow] of [['new-member', true], ['revoked', false]]) {
    const join = await restart.join(id);
    await restart.respond('VERIFY_WHITELIST', 'offline', false);
    const reason = await restart.finish(join);
    assert.equal(reason === undefined, shouldAllow, 'Persisted live allow/deny decisions must survive resource restarts');
  }

  const off = await scenario({ enabled: false });
  assert.equal(off.events.size, 0);
  assert.equal(off.requests.length, 0);
}

async function outageAndDiskChecks() {
  for (const failure of ['write', 'rename']) {
    const s = await scenario({ cache: saved() });
    const previousDisk = s.files.get(backupPath);
    s.failures[failure] = true;
    await s.respond('FULL_WHITELIST', snapshot(true, 'new-member'));
    assert.equal(s.files.get(backupPath), previousDisk, `${failure} failure must preserve the previous disk cache`);
    const join = await s.join('new-member');
    await s.respond('VERIFY_WHITELIST', 'offline', false);
    assert.equal(await s.finish(join), undefined, 'A disk failure must retain the newer in-memory cache');
  }

  const timeout = await scenario({ cache: saved() });
  await timeout.respond('FULL_WHITELIST', 'offline', false);
  const join = await timeout.join('member');
  const request = timeout.pending('VERIFY_WHITELIST');
  await timeout.advance(10000);
  assert.equal(await timeout.finish(join), undefined);
  request.callback('NOT ALLOWED ON WHITELIST', false);
  await timeout.advance(0);
  assert.equal(join.done.length, 1, 'Late API replies must not finish a deferred join twice');
  assert.deepEqual(timeout.disk().apiIds, ['member']);

  const fresh = await scenario();
  const first = await fresh.join('first');
  const second = await fresh.join('second', 11);
  assert.equal(fresh.requests.filter((request) => request.type === 'FULL_WHITELIST').length, 1,
    'Startup and simultaneous joins must share one snapshot request');
  await fresh.advance(20000);
  assert.match(await fresh.finish(first), /no valid whitelist backup/);
  assert.match(await fresh.finish(second), /no valid whitelist backup/);
  assert.equal(fresh.files.has(backupPath), false, 'A complete callback outage must not invent a backup');
}

async function snapshotThrottleChecks() {
  const disabled = await scenario();
  await disabled.respond('FULL_WHITELIST', snapshot(false));
  for (let index = 0; index < 3; index++) {
    const join = await disabled.join(null, index + 50);
    assert.equal(await disabled.finish(join), undefined);
  }
  assert.equal(disabled.requests.length, 1, 'Sequential unrestricted joins must reuse the recent disabled snapshot');

  const outage = await scenario();
  await outage.respond('FULL_WHITELIST', 'offline', false);
  const deniedJoin = async (source) => {
    const join = await outage.join('unknown', source);
    await outage.respond('VERIFY_WHITELIST', 'offline', false);
    assert.match(await outage.finish(join), /no valid whitelist backup/);
  };
  await deniedJoin(60);
  await deniedJoin(61);
  await outage.advance(29999);
  await deniedJoin(62);
  assert.equal(outage.requests.filter((request) => request.type === 'FULL_WHITELIST').length, 1,
    'Failed snapshot attempts must also be shared across sequential joins for thirty seconds');
  await outage.advance(1);
  const retry = await outage.join('unknown', 63);
  assert.equal(outage.requests.filter((request) => request.type === 'FULL_WHITELIST').length, 2,
    'The next join must retry after the snapshot throttle expires');
  await outage.respond('FULL_WHITELIST', 'offline', false);
  await outage.respond('VERIFY_WHITELIST', 'offline', false);
  assert.match(await outage.finish(retry), /no valid whitelist backup/);
}

async function rankUpdateChecks() {
  const s = await scenario({ cache: saved() });
  await s.respond('FULL_WHITELIST', snapshot(true, 'member'));
  s.players.set(21, { id: 'removed', name: 'Connected player' });
  const outage = s.rankUpdate();
  await s.respond('FULL_WHITELIST', 'offline', false);
  await s.respond('VERIFY_WHITELIST', 'offline', false);
  await outage;
  assert.deepEqual(s.drops, [], 'A snapshot outage must never kick connected players');

  const uncertain = s.rankUpdate();
  await s.respond('FULL_WHITELIST', snapshot(true));
  await s.respond('VERIFY_WHITELIST', 'offline', false);
  await uncertain;
  assert.deepEqual(s.drops, [], 'An individual verification outage must never kick connected players');

  const reused = s.rankUpdate();
  await s.respond('FULL_WHITELIST', snapshot(true));
  s.players.set(21, { id: 'replacement', name: 'New player with reused source' });
  await s.respond('VERIFY_WHITELIST', 'NOT ALLOWED ON WHITELIST', false);
  await reused;
  assert.deepEqual(s.drops, [], 'A source ID reused while CMS responds must not kick its replacement');

  const denied = s.rankUpdate();
  await s.respond('FULL_WHITELIST', snapshot(true));
  await s.respond('VERIFY_WHITELIST', 'BLOCKED FOR WHITELIST', false);
  await denied;
  assert.equal(s.drops.length, 1);
  assert.equal(s.drops[0].source, 21);
  assert.match(s.drops[0].reason, /BLOCKED FOR WHITELIST/);

  const disabled = await scenario({ cache: saved({ enabled: false, apiIds: [] }) });
  await disabled.respond('FULL_WHITELIST', 'offline', false);
  disabled.players.set(30, { id: 'revoked', name: 'Previously unrestricted player' });
  const revokeDisabled = disabled.rankUpdate();
  await disabled.respond('FULL_WHITELIST', 'offline', false);
  await disabled.respond('VERIFY_WHITELIST', 'NOT ALLOWED ON WHITELIST', false);
  await revokeDisabled;
  assert.equal(disabled.drops.length, 1, 'An explicit live denial must override cached disabled mode');
  assert.equal(disabled.disk().enabled, true);

  const queued = await scenario({ cache: saved() });
  await queued.respond('FULL_WHITELIST', snapshot(true, 'member'));
  queued.players.set(31, { id: 'member', name: 'Rank changes during refresh' });
  const firstPass = queued.rankUpdate();
  await flush();
  await queued.rankUpdate();
  await queued.respond('FULL_WHITELIST', snapshot(true, 'member'));
  await queued.respond('FULL_WHITELIST', snapshot(true));
  await queued.respond('VERIFY_WHITELIST', 'NOT ALLOWED ON WHITELIST', false);
  await firstPass;
  assert.equal(queued.drops.length, 1, 'A rank event during a recheck must trigger another pass');
}

async function periodicRecheckChecks() {
  const recovery = await scenario({ cache: saved({ apiIds: ['revoked'] }) });
  await recovery.respond('FULL_WHITELIST', snapshot(true, 'revoked'));
  recovery.players.set(70, { id: 'revoked', name: 'Revocation deferred during outage' });
  const deferred = recovery.rankUpdate();
  await recovery.respond('FULL_WHITELIST', snapshot(true));
  await recovery.respond('VERIFY_WHITELIST', 'offline', false);
  await deferred;
  assert.deepEqual(recovery.drops, [], 'A failed verification must defer the revocation');
  await recovery.advance(5 * 60 * 1000);
  await recovery.respond('FULL_WHITELIST', snapshot(true));
  await recovery.respond('VERIFY_WHITELIST', 'NOT ALLOWED ON WHITELIST', false);
  assert.equal(recovery.drops.length, 1, 'The periodic refresh must retry deferred revocations after CMS recovers');
  assert.equal(recovery.drops[0].source, 70);

  const missing = await scenario({ cache: saved() });
  await missing.respond('FULL_WHITELIST', snapshot(true, 'member'));
  missing.players.set(71, { id: null, name: 'Player without configured identifier' });
  const unavailable = missing.rankUpdate();
  await missing.respond('FULL_WHITELIST', 'offline', false);
  await unavailable;
  assert.deepEqual(missing.drops, [], 'An unavailable snapshot must not kick a connected player without an identifier');
  const authoritative = missing.rankUpdate();
  await missing.respond('FULL_WHITELIST', snapshot(true));
  await authoritative;
  assert.equal(missing.drops.length, 1, 'A fresh enabled snapshot must enforce its identifier requirement');
  assert.equal(missing.drops[0].source, 71);
  assert.match(missing.drops[0].reason, /discord identifier/);
  assert.equal(missing.requests.filter((request) => request.type === 'VERIFY_WHITELIST').length, 0,
    'A missing identifier must never be sent to individual verification');

  const unavailableApi = await scenario();
  await unavailableApi.respond('FULL_WHITELIST', snapshot(true));
  for (const source of [72, 73, 74]) {
    unavailableApi.players.set(source, { id: `unknown-${source}`, name: `Player ${source}` });
  }
  const recheck = unavailableApi.rankUpdate();
  await unavailableApi.respond('FULL_WHITELIST', snapshot(true));
  assert.equal(unavailableApi.pending('VERIFY_WHITELIST').data.apiId, 'unknown-72');
  await unavailableApi.advance(10000);
  await recheck;
  assert.equal(unavailableApi.requests.filter((request) => request.type === 'VERIFY_WHITELIST').length, 1,
    'After the first backend timeout, stop instead of waiting ten seconds for each remaining player');
  assert.deepEqual(unavailableApi.drops, []);
}

async function run() {
  await helperChecks();
  await snapshotChecks();
  await invalidCacheChecks();
  await modeAndDecisionChecks();
  await outageAndDiskChecks();
  await snapshotThrottleChecks();
  await rankUpdateChecks();
  await periodicRecheckChecks();
  console.log('whitelist backup: snapshots, atomic disk writes, scope, modes, offline decisions, timeouts, and rank updates passed');
}

const watchdog = setTimeout(() => {
  console.error('Whitelist tests stalled on an unfinished async operation');
  process.exitCode = 1;
}, 5000);
run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => clearTimeout(watchdog));
