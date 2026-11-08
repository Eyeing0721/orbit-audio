import { cp, mkdir, readFile, writeFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = path.join(root, 'dist');
const origin = new URL(process.env.ORBIT_SITE_URL || 'https://orbit-audio.pages.dev').origin;
if (!origin.startsWith('https://') && !origin.startsWith('http://127.0.0.1:')) {
  throw new Error('ORBIT_SITE_URL must be HTTPS or a local preview address');
}
await mkdir(dist, { recursive: true });
for (const name of ['index.html', 'styles.css', 'app.js', '404.html', '_headers']) {
  const text = await readFile(path.join(root, name), 'utf8');
  await writeFile(path.join(dist, name), text.replaceAll('__SITE_URL__', origin));
}
await cp(path.join(root, 'assets'), path.join(dist, 'assets'), { recursive: true });
await writeFile(path.join(dist, 'robots.txt'), 'User-agent: *\nAllow: /\nSitemap: ' + origin + '/sitemap.xml\n');
await writeFile(path.join(dist, 'sitemap.xml'), '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>' + origin + '/</loc></url></urlset>\n');
const entries = await readdir(dist);
console.log('Static website built: ' + entries.length + ' top-level entries; origin ' + origin);
