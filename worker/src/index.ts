// Cloudflare Worker that proxies the docs site from a free `*.workers.dev`
// hostname to the Oracle VM. Lets us run the docs site without buying a
// domain and without terminating TLS on the VM — Cloudflare handles HTTPS
// at the Worker edge, then talks to the origin over plain HTTP.
//
// The Worker also adds a shared-secret header so Caddy on the VM can refuse
// requests that didn't come through the Worker, preventing IP-based
// bypass of the free-tier metering.

interface Env {
	/** Origin URL of the Oracle VM, e.g. http://152.67.1.2 */
	ORIGIN: string;
	/** Shared secret echoed in X-Worker-Secret; Caddy on the VM checks for it. */
	WORKER_SECRET: string;
}

const HOP_BY_HOP = new Set([
	'connection',
	'keep-alive',
	'proxy-authenticate',
	'proxy-authorization',
	'te',
	'trailers',
	'transfer-encoding',
	'upgrade',
]);

function stripHopByHop(headers: Headers): Headers {
	const out = new Headers();
	for (const [k, v] of headers) {
		if (!HOP_BY_HOP.has(k.toLowerCase())) out.set(k, v);
	}
	return out;
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		const url = new URL(request.url);
		const upstream = new URL(url.pathname + url.search, env.ORIGIN);

		// Cache static assets aggressively — Astro fingerprints filenames in
		// /_astro/ so they're safe to cache forever. Doc pages cache for a
		// minute so a deploy propagates within the cache TTL.
		const cacheKey = new Request(url.toString(), { method: 'GET' });
		const cache = caches.default;
		const isAsset = url.pathname.startsWith('/_astro/');
		if (request.method === 'GET') {
			const hit = await cache.match(cacheKey);
			if (hit) return hit;
		}

		const headers = stripHopByHop(request.headers);
		headers.set('X-Worker-Secret', env.WORKER_SECRET);
		headers.set('X-Forwarded-Host', url.host);
		headers.set('X-Forwarded-Proto', 'https');

		const upstreamReq = new Request(upstream.toString(), {
			method: request.method,
			headers,
			body: request.method === 'GET' || request.method === 'HEAD' ? null : request.body,
			redirect: 'manual',
		});

		let res: Response;
		try {
			res = await fetch(upstreamReq);
		} catch (err) {
			return new Response(`Origin unreachable: ${err instanceof Error ? err.message : String(err)}`, {
				status: 502,
			});
		}

		// Build a mutable response we can attach cache headers to.
		const resHeaders = stripHopByHop(res.headers);
		if (request.method === 'GET' && res.ok) {
			if (isAsset) {
				resHeaders.set('Cache-Control', 'public, max-age=31536000, immutable');
			} else if (!resHeaders.has('Cache-Control')) {
				resHeaders.set('Cache-Control', 'public, max-age=60');
			}
		}

		const piped = new Response(res.body, {
			status: res.status,
			statusText: res.statusText,
			headers: resHeaders,
		});

		if (request.method === 'GET' && res.ok) {
			ctx.waitUntil(cache.put(cacheKey, piped.clone()));
		}
		return piped;
	},
} satisfies ExportedHandler<Env>;
