import { readFile, appendFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { basename, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function planNpmRelease(folder, { sourceCommit, packageName, version, fetchRegistry = fetch }) {
  if (!/^[a-f0-9]{40}$/i.test(sourceCommit ?? '')) throw new Error('A complete source commit is required');
  const readJson = async (name) => JSON.parse(await readFile(resolve(folder, name), 'utf8'));
  const receipt = await readJson('archive-result.json');
  if (receipt.sourceCommit !== sourceCommit || ![
    'passed', 'coreSourceByteEquivalent', 'pubSelectedCoreAndWrapper',
    'actualNpmPack', 'archivedExampleBuilt', 'archivedExampleBrowser',
  ].every((gate) => receipt[gate] === true)) {
    throw new Error('The npm archive is not verified for this source commit');
  }
  const packs = await readJson('npm-pack.json');
  if (packs.length !== 1 || packs[0].name !== packageName || packs[0].version !== version ||
      basename(packs[0].filename) !== packs[0].filename || !packs[0].filename.endsWith('.tgz')) {
    throw new Error('The verified npm archive does not match the selected package version');
  }
  const archive = resolve(folder, packs[0].filename);
  const archiveBytes = await readFile(archive);
  const response = await fetchRegistry(`https://registry.npmjs.org/${encodeURIComponent(packageName)}/${encodeURIComponent(version)}`);
  if (response.status !== 200 && response.status !== 404) {
    throw new Error(`npm version lookup failed: HTTP ${response.status}`);
  }
  if (response.status === 200) {
    const published = await response.json();
    const integrity = 'sha512-' + createHash('sha512').update(archiveBytes).digest('base64');
    if (published.dist?.integrity !== integrity) {
      throw new Error('This npm version already exists with different archive bytes; select a new version');
    }
  }
  return { archive, publish: response.status === 404 };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const { name: packageName, version } = JSON.parse(await readFile(new URL('../web/package.json', import.meta.url), 'utf8'));
  const plan = await planNpmRelease(process.argv[2], { sourceCommit: process.env.GITHUB_SHA, packageName, version });
  await appendFile(process.env.GITHUB_OUTPUT, `publish=${plan.publish}\narchive=${plan.archive}\n`);
  console.log(plan.publish ? `Publish verified ${packageName}@${version}` : `${packageName}@${version} is already published; skipping`);
}
