// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import node from '@astrojs/node';
import mermaid from 'astro-mermaid';

// Static-by-default; the Node adapter lets individual routes opt into SSR
// via `export const prerender = false`. /api/search uses that to query sqld
// at request time. Astro 6 has no `hybrid` mode — this is the equivalent.
export default defineConfig({
	site: 'https://docs.sqlitedeploy.dev',
	output: 'static',
	adapter: node({ mode: 'standalone' }),
	integrations: [
		// Must come BEFORE starlight — astro-mermaid registers a remark plugin
		// that needs to run before Starlight's markdown pipeline locks in.
		mermaid({
			// Picks the same dark/light theme as Starlight (which toggles
			// data-theme on <html>) so diagrams don't look out of place.
			autoTheme: true,
			theme: 'default',
		}),
		starlight({
			title: 'sqlitedeploy',
			description: 'Deploy SQLite as a real database — sqld + your own object storage, free tier friendly.',
			customCss: ['./src/styles/global.css'],
			head: [
				{
					tag: 'link',
					attrs: { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
				},
				{
					tag: 'link',
					attrs: { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
				},
				{
					tag: 'link',
					attrs: {
						rel: 'stylesheet',
						href: 'https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700;800&family=Space+Grotesk:wght@400;500;600;700&display=swap',
					},
				},
			],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/Khangdang1690/sqlitedeploy' },
			],
			components: {
				// Replace Starlight's built-in Pagefind search with one backed by
				// a sqld FTS5 index (populated at build time by scripts/index-search.ts).
				Search: './src/components/SearchBox.astro',
				SiteTitle: './src/components/SiteTitle.astro',
			},
			sidebar: [
				{
					label: 'Start here',
					items: [
						{ label: 'What is sqlitedeploy?', slug: 'index' },
						{ label: 'Quickstart', slug: 'guides/quickstart' },
						{ label: 'How it works', slug: 'guides/how-it-works' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Local dev (no cloud)', slug: 'guides/local-dev' },
						{ label: 'Bring your own storage', slug: 'guides/byo-storage' },
						{ label: 'Deploy on any cloud', slug: 'guides/deploy' },
						{ label: 'Read replicas', slug: 'guides/replicas' },
						{ label: 'Connecting from edge runtimes', slug: 'guides/edge-clients' },
						{ label: 'Benchmarks', slug: 'guides/benchmarks' },
						{ label: 'Pricing vs Postgres', slug: 'guides/pricing' },
					],
				},
				{
					label: 'CLI reference',
					items: [{ autogenerate: { directory: 'reference' } }],
				},
			],
		}),
	],
});
