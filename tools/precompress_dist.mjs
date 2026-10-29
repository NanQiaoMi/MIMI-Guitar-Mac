import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

function compressDir(dir) {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      compressDir(fullPath);
    } else if (entry.isFile()) {
      const ext = path.extname(entry.name).toLowerCase();
      if (['.js', '.css', '.json', '.svg', '.ttf', '.otf', '.woff', '.html', '.txt'].includes(ext)) {
        const content = fs.readFileSync(fullPath);
        if (content.length > 512) {
          const gzipped = zlib.gzipSync(content, { level: 9 });
          fs.writeFileSync(`${fullPath}.gz`, gzipped);
        }
      }
    }
  }
}

console.log('Pre-compressing dist/client assets for gzip_static...');
compressDir('dist/client');
console.log('✓ Pre-compression complete!');
