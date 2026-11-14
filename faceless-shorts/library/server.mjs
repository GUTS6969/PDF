#!/usr/bin/env node
/**
 * Faceless Shorts Library
 * A dependency-free local gallery for rendered projects. It deliberately scans
 * the normal ~/faceless-shorts project directory instead of copying videos.
 */
import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(here, 'public');
const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};
const libraryRoot = path.resolve(option('--root', process.env.FACELESS_LIBRARY_ROOT || path.join(os.homedir(), 'faceless-shorts')));
const host = option('--host', process.env.HOST || '0.0.0.0');
const port = Number(option('--port', process.env.PORT || '4173'));
const MIME = {
  '.css': 'text/css; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.json': 'application/json; charset=utf-8', '.mp4': 'video/mp4',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.wav': 'audio/wav',
};
const ignored = new Set(['.git', 'node_modules', '.DS_Store', '_selftest', 'review', 'data', 'fonts', 'vendor']);

function safePath(root, requested) {
  const file = path.resolve(root, requested);
  return file === root || file.startsWith(`${root}${path.sep}`) ? file : null;
}
function humanize(value) {
  return value.replace(/[-_]+/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}
function relativeUrl(file) {
  return `/media?path=${encodeURIComponent(path.relative(libraryRoot, file))}`;
}
async function readJson(file) {
  try { return JSON.parse(await fsp.readFile(file, 'utf8')); } catch { return null; }
}
async function firstExisting(files) {
  for (const file of files) {
    try { if ((await fsp.stat(file)).isFile()) return file; } catch { /* keep looking */ }
  }
  return null;
}
async function walk(directory, depth = 0, found = []) {
  if (depth > 4) return found;
  let entries;
  try { entries = await fsp.readdir(directory, { withFileTypes: true }); } catch { return found; }
  await Promise.all(entries.map(async (entry) => {
    if (entry.name.startsWith('.') || ignored.has(entry.name)) return;
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'renders') {
        let renders = [];
        try { renders = await fsp.readdir(file, { withFileTypes: true }); } catch { return; }
        for (const render of renders) {
          if (render.isFile() && /\.mp4$/i.test(render.name)) found.push(path.join(file, render.name));
        }
      } else {
        await walk(file, depth + 1, found);
      }
    } else if (entry.isFile() && /\.mp4$/i.test(entry.name)) {
      found.push(file);
    }
  }));
  return found;
}
async function videoEntry(file) {
  const stat = await fsp.stat(file);
  const renderDir = path.dirname(file);
  const project = path.basename(renderDir) === 'renders' ? path.dirname(renderDir) : renderDir;
  const script = await readJson(path.join(project, 'script.json'));
  const projectMeta = await readJson(path.join(project, '.faceless-short.json'));
  const name = path.basename(project);
  const preview = await firstExisting([
    path.join(project, 'review', 'cover.jpg'), path.join(project, 'review', 'cover.png'),
    path.join(project, 'review', 'all.jpg'), path.join(project, 'review', 'all.png'),
  ]);
  const style = projectMeta?.style || script?.style || script?.template || null;
  return {
    id: path.relative(libraryRoot, file),
    title: script?.title || humanize(path.basename(file, path.extname(file))) || humanize(name),
    project: name,
    style: style ? humanize(style) : 'Faceless short',
    createdAt: stat.mtime.toISOString(),
    size: stat.size,
    videoUrl: relativeUrl(file),
    posterUrl: preview ? relativeUrl(preview) : null,
    projectPath: path.relative(libraryRoot, project),
  };
}
async function videos() {
  const files = await walk(libraryRoot);
  return (await Promise.all(files.map(videoEntry))).sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
}
function json(response, body, status = 200) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify(body));
}
async function media(request, response, url) {
  const requested = url.searchParams.get('path');
  const file = requested && safePath(libraryRoot, requested);
  if (!file) return json(response, { error: 'Invalid media path.' }, 400);
  let stat;
  try { stat = await fsp.stat(file); } catch { return json(response, { error: 'File not found.' }, 404); }
  if (!stat.isFile()) return json(response, { error: 'Not a file.' }, 404);
  const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
  const range = request.headers.range;
  if (range && /^bytes=\d*-\d*$/.test(range)) {
    const [rawStart, rawEnd] = range.replace('bytes=', '').split('-');
    const start = rawStart ? Number(rawStart) : 0;
    const end = rawEnd ? Math.min(Number(rawEnd), stat.size - 1) : stat.size - 1;
    if (start > end || start >= stat.size) { response.writeHead(416, { 'Content-Range': `bytes */${stat.size}` }); return response.end(); }
    response.writeHead(206, { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Content-Length': end - start + 1 });
    return fs.createReadStream(file, { start, end }).pipe(response);
  }
  response.writeHead(200, { 'Content-Type': type, 'Content-Length': stat.size, 'Accept-Ranges': 'bytes' });
  fs.createReadStream(file).pipe(response);
}
async function staticFile(response, pathname) {
  const name = pathname === '/' ? 'index.html' : pathname.slice(1);
  const file = safePath(publicDir, name);
  if (!file) return json(response, { error: 'Not found.' }, 404);
  try {
    const content = await fsp.readFile(file);
    response.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    response.end(content);
  } catch { json(response, { error: 'Not found.' }, 404); }
}
const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
  if (url.pathname === '/api/videos') return json(response, { root: libraryRoot, videos: await videos() });
  if (url.pathname === '/api/health') return json(response, { ok: true, root: libraryRoot });
  if (url.pathname === '/media') return media(request, response, url);
  return staticFile(response, url.pathname);
});
server.listen(port, host, () => {
  console.log(`Faceless Shorts Library: http://${host}:${port}`);
  console.log(`Watching rendered videos in: ${libraryRoot}`);
});
