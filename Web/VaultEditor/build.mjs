import { build } from 'esbuild';
import { mkdir, readFile, writeFile, copyFile, access } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const upstream = resolve('.upstream/obsidian-dataview-0.5.68');
if (!existsSync(upstream)) {
  const response = await fetch('https://github.com/blacksmithgu/obsidian-dataview/archive/refs/tags/0.5.68.tar.gz');
  if (!response.ok) throw Error('Dataview source download failed');
  const archive = Buffer.from(await response.arrayBuffer());
  if (createHash('sha256').update(archive).digest('hex') !== '3f8144fb1b90653999aec9d6da50dd36bcc33c64ca07f23c9c2f916d6b8adfb9') throw Error('Dataview archive checksum mismatch');
  await mkdir('.upstream', { recursive: true });
  await writeFile('.upstream/dataview.tar.gz', archive);
  execFileSync('tar', ['-xzf','.upstream/dataview.tar.gz','-C','.upstream']);
}
const out = resolve('../../HorongHorong/Resources/VaultEditor');
await mkdir(out, { recursive: true });
const plugin = {
  name: 'dataview-core', setup(builder) {
    builder.onResolve({ filter: /^(api|data-import|data-model|data-index|expression|query|util)\/|^settings$/ }, args => {
      if (args.path === 'data-index/index') return { path: resolve('src/dataview-index-shim.ts') };
      return { path: resolve(upstream,'src', args.path + '.ts') };
    });
  }
};
const common = { bundle: true, target: 'safari17', plugins: [plugin], nodePaths: [resolve('node_modules')], logLevel: 'info', legalComments: 'linked' };
for (const entry of ['editor','runtime']) await build({ ...common, entryPoints: [`src/${entry}.js`], outfile: `${out}/${entry}.js`, minify: true, format: 'iife', loader: { '.woff2':'file','.woff':'file','.ttf':'file' } });
await build({ ...common, entryPoints: ['src/test-exports.js'], outfile: 'test-bundle.mjs', format: 'esm', platform: 'node', banner: { js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);" } });
for (const name of ['index.html','runtime.html','style.css','obsidian-compat.css','obsidian-snippets.css']) await copyFile(`src/${name}`,`${out}/${name}`);
await copyFile(`${upstream}/LICENSE.txt`,`${out}/DATAVIEW-LICENSE.txt`);
const names = Object.keys(JSON.parse(await readFile('package.json','utf8')).dependencies);
let licenses = 'Bundled dependencies (versions are pinned in Web/VaultEditor/package-lock.json)\n';
for (const name of names) {
  for (const candidate of ['LICENSE','LICENSE.md','LICENSE.txt','license','license.md']) {
    try { licenses += `\n\n${name}\n${await readFile(resolve('node_modules',name,candidate),'utf8')}`; break; } catch {}
  }
}
await writeFile(`${out}/THIRD-PARTY-LICENSES.txt`,licenses);
