import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { planNpmRelease } from './npm_release.mjs';

const sourceCommit = 'a'.repeat(40);
const packageName = '@festapp/venue-layout';
const version = '0.3.5';
const archiveBytes = 'archive existence fixture; archive contents are owned by the archive gate';
async function fixture(t, { commit = sourceCommit, packVersion = version, passed = true } = {}) {
  const folder = await mkdtemp(join(tmpdir(), 'npm-release-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  await writeFile(join(folder, 'archive-result.json'), JSON.stringify({
    sourceCommit: commit, passed, coreSourceByteEquivalent: true,
    pubSelectedCoreAndWrapper: true, actualNpmPack: true,
    archivedExampleBuilt: true, archivedExampleBrowser: true,
  }));
  await writeFile(join(folder, 'npm-pack.json'), JSON.stringify([
    { name: packageName, version: packVersion, filename: 'verified.tgz' },
  ]));
  await writeFile(join(folder, 'verified.tgz'), archiveBytes);
  return folder;
}

test('a missing version publishes the verified archive and an existing version skips it', async (t) => {
  const folder = await fixture(t);
  for (const status of [404, 200]) {
    const result = await planNpmRelease(folder, {
      sourceCommit, packageName, version,
      fetchRegistry: async (url) => {
        assert.equal(url, 'https://registry.npmjs.org/%40festapp%2Fvenue-layout/0.3.5');
        return { status, json: async () => ({ dist: { integrity: 'sha512-' + createHash('sha512').update(archiveBytes).digest('base64') } }) };
      },
    });
    assert.equal(result.archive, join(folder, 'verified.tgz'));
    assert.equal(result.publish, status === 404);
  }
});

for (const changed of [{ commit: 'b'.repeat(40) }, { packVersion: '0.3.4' }, { passed: false }]) {
  test(`unverified or mismatched archive stops before registry access: ${JSON.stringify(changed)}`, async (t) => {
    const folder = await fixture(t, changed);
    await assert.rejects(planNpmRelease(folder, {
      sourceCommit, packageName, version,
      fetchRegistry: () => assert.fail('Registry must not be contacted for an invalid archive'),
    }), /not verified|does not match/);
  });
}

for (const status of [401, 500]) {
  test(`registry HTTP ${status} cannot be mistaken for an unpublished version`, async (t) => {
    const folder = await fixture(t);
    await assert.rejects(planNpmRelease(folder, {
      sourceCommit, packageName, version, fetchRegistry: async () => ({ status }),
    }), new RegExp(`HTTP ${status}`));
  });
}

test('an existing version with different bytes cannot be treated as a successful retry', async (t) => {
  const folder = await fixture(t);
  await assert.rejects(planNpmRelease(folder, {
    sourceCommit, packageName, version,
    fetchRegistry: async () => ({ status: 200, json: async () => ({ dist: { integrity: 'sha512-other' } }) }),
  }), /already exists with different archive bytes/);
});
