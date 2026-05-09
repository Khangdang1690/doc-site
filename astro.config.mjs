// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import node from '@astrojs/node';

// Static-by-default; the Node adapter lets individual routes opt into SSR
// via `export const prerender = false`. /api/search uses that to query sqld
// at request time. Astro 6 has no `hybrid` mode — this is the equivalent.
export default defineConfig({
	site: 'https://docs.sqlitedeploy.dev',
	output: 'static',
	adapter: node({ mode: 'standalone' }),
	integrations: [
		starlight({
			title: 'sqlitedeploy',
			description: 'Deploy SQLite as a real database — sqld + your own object storage, free tier friendly.',
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/Khangdang1690/sqlitedeploy' },
			],
			components: {
				// Replace Starlight's built-in Pagefind search with one backed by
				// a sqld FTS5 index (populated at build time by scripts/index-search.ts).
				Search: './src/components/SearchBox.astro',
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
						{ label: 'Read replicas', slug: 'guides/replicas' },
						{ label: 'Connecting from edge runtimes', slug: 'guides/edge-clients' },
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
