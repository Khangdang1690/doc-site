import type { APIRoute } from 'astro';
import { createClient, type Client, type InValue } from '@libsql/client';

export const prerender = false;

let cached: Client | null = null;

function db(): Client {
	if (cached) return cached;
	const url = import.meta.env.LIBSQL_URL ?? process.env.LIBSQL_URL;
	const authToken = import.meta.env.LIBSQL_AUTH_TOKEN ?? process.env.LIBSQL_AUTH_TOKEN;
	if (!url) throw new Error('LIBSQL_URL not configured');
	cached = createClient({ url, authToken });
	return cached;
}

// FTS5 prefix-match query. Whitespace splits the user query into terms, each
// becomes `term*` so partial typing matches. The asterisk is FTS5's prefix
// operator; quotes guard against syntax characters in user input.
function buildMatch(q: string): string {
	return q
		.split(/\s+/)
		.filter(Boolean)
		.slice(0, 8)
		.map((t) => `"${t.replace(/"/g, '""')}"*`)
		.join(' ');
}

export const GET: APIRoute = async ({ url }) => {
	const q = url.searchParams.get('q')?.trim() ?? '';
	if (q.length < 2) {
		return new Response('[]', {
			headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=60' },
		});
	}

	const match: InValue = buildMatch(q);

	try {
		const result = await db().execute({
			sql: `SELECT slug, title, description,
			             snippet(docs_fts, 3, '<mark>', '</mark>', '…', 12) AS snippet
			      FROM docs_fts
			      WHERE docs_fts MATCH ?
			      ORDER BY rank
			      LIMIT 10`,
			args: [match],
		});

		return Response.json(result.rows, {
			headers: { 'cache-control': 'public, max-age=60' },
		});
	} catch (err) {
		// Common causes:
		//   - sqld not running on LIBSQL_URL
		//   - JWT signed by a different keypair than this sqld expects
		//   - docs_fts table missing (run `pnpm postbuild` to populate)
		const message = err instanceof Error ? err.message : String(err);
		return Response.json({ error: message }, { status: 500 });
	}
};
