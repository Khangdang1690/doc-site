// Build-time FTS5 indexer.
//
// Walks src/content/docs/**/*.{md,mdx}, strips Markdown to plain text, and
// rebuilds the docs_fts virtual table on the live sqld primary. Runs as the
// `postbuild` npm script so it executes on the VM right after `astro build`,
// against the local sqld at 127.0.0.1:8080.
//
// Required env:
//   LIBSQL_URL          e.g. http://127.0.0.1:8080
//   LIBSQL_AUTH_TOKEN   contents of .sqlitedeploy/auth/replica.jwt
//
// In local dev (no sqld running) this script is a no-op: leave LIBSQL_URL
// unset to skip the connection.

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fg from 'fast-glob';
import matter from 'gray-matter';
import { remark } from 'remark';
import strip from 'strip-markdown';
import { createClient } from '@libsql/client';

const url = process.env.LIBSQL_URL;
const authToken = process.env.LIBSQL_AUTH_TOKEN;

if (!url) {
	console.log('[index-search] LIBSQL_URL unset — skipping reindex (local dev mode).');
	process.exit(0);
}

const root = path.resolve(fileURLToPath(import.meta.url), '../..');
const contentDir = path.join(root, 'src/content/docs');
const files = await fg('**/*.{md,mdx}', { cwd: contentDir, absolute: true });

if (files.length === 0) {
	console.warn('[index-search] No content files found under', contentDir);
	process.exit(0);
}

const stripper = remark().use(strip);

type Doc = { slug: string; title: string; description: string; body: string };

const docs: Doc[] = await Promise.all(files.map(async (file) => {
	const raw = await readFile(file, 'utf8');
	const { data, content } = matter(raw);
	const plain = String(await stripper.process(content)).replace(/\s+/g, ' ').trim();
	const rel = path.relative(contentDir, file).replace(/\\/g, '/');
	const slug = rel.replace(/\.(md|mdx)$/, '').replace(/\/index$/, '');
	return {
		slug,
		title: typeof data.title === 'string' ? data.title : slug,
		description: typeof data.description === 'string' ? data.description : '',
		body: plain,
	};
}));

const db = createClient({ url, authToken });

await db.executeMultiple(`
	DROP TABLE IF EXISTS docs_fts;
	CREATE VIRTUAL TABLE docs_fts USING fts5(
		slug UNINDEXED,
		title,
		description,
		body,
		tokenize = 'porter unicode61'
	);
`);

await db.batch(
	docs.map((d) => ({
		sql: 'INSERT INTO docs_fts(slug,title,description,body) VALUES (?,?,?,?)',
		args: [d.slug, d.title, d.description, d.body],
	})),
	'write',
);

console.log(`[index-search] Indexed ${docs.length} pages into docs_fts.`);
