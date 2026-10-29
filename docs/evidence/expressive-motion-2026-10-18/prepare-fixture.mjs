import { readFile, writeFile } from 'node:fs/promises';

// Repeat our own two-bar melody, with unique identifiers, for a bounded UI playback check.
const project = JSON.parse(await readFile(new URL('../studio-interactions-2026-10-17/self-authored-studio.json', import.meta.url), 'utf8'));
const originalBars = project.bars;
function copyWithIds(value, prefix) {
  if (Array.isArray(value)) return value.map((entry) => copyWithIds(entry, prefix));
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key,
    key === 'id' && typeof entry === 'string' ? `${prefix}-${entry}` : copyWithIds(entry, prefix),
  ]));
}
project.id = 'expressive-motion-acceptance-20261018';
project.title = '动效与工具验收 · 自写十六小节';
project.initialTempo = 60;
project.bars = Array.from({ length: 16 }, (_, index) => {
  const bar = copyWithIds(originalBars[index % originalBars.length], `motion-${index}`);
  return { ...bar, index, tempo: 60, section: index === 0 ? '自写验收练习' : '' };
});
await writeFile(new URL('self-authored-motion.json', import.meta.url), JSON.stringify(project, null, 2) + '\n');
console.log('Prepared self-authored 16-bar / 60 BPM fixture. Import only through the product file chooser.');
