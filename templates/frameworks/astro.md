# Astro rules

- Zero JS by default. Add islands (`client:*`) only for real interactivity; static content ships no JS.
- Content lives in Content Collections with a typed, validated frontmatter schema — never loose markdown folders.
- SEO baseline on every page: unique `<title>` (max 60 chars) and meta description (max 155), canonical URL, Open Graph + Twitter cards, JSON-LD matching the page type, sitemap and RSS where applicable.
- Never ship fake structured data (invented ratings/reviews) — it can penalize the domain. Every CTA must reflect exactly what happens on click.
- Derive listings (categories, tags, counts) dynamically from content — never hardcode them.
- One `.astro` component per page section, small and focused. Tailwind utilities in components; global CSS only for tokens/imports.
