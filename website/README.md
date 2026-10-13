# Crumbs website

The marketing site for [Crumbs](https://github.com/SidhuK/Crumbs), a free and open source menu bar app for macOS. It's a single static page built with [Astro](https://astro.build) and [Tailwind CSS](https://tailwindcss.com).

## Running it

You need [Bun](https://bun.sh).

```bash
bun install
bun run dev      # local dev server at http://localhost:4321
bun run build    # static site in dist/
bun run preview  # serve the built site
```

## Deploying

On Vercel, set the project's Root Directory to `website`. Vercel picks up Astro and Bun on its own, and the build output is `dist/`.

Astro needs the site's address for the canonical and Open Graph URLs and the sitemap. On Vercel it uses the project's production domain automatically. Anywhere else, or to use a different domain, set the `SITE_URL` environment variable (for example `https://crumbs.app`).

## Where things live

- `src/site.ts` holds the name, tagline, description and links. Every section reads from it.
- `src/styles/global.css` holds the colors, fonts and shared styles such as `.btn-ink`, `.kbd`, the highlighter marks and the grid paper.
- `src/components/` has one file per section of the page. `scripts/gen-dither.py` regenerates the dither cloud images (needs Pillow).
- `public/images/` has the app icon and screenshots, all at 2x. They show the app with sample notes, like the screenshots in `../docs/images`. To update one, replace the file with an image of the same size.
- `public/images/og.png` is the 1200×630 social preview image.
- `public/images/crumbs-demo.{webm,mp4}` is the demo video (1600×972, 30 fps, no audio) shown in the hero, with `crumbs-demo-poster.webp` as its poster frame. The README uses a GIF of the same video at `../docs/images/demo.gif`.
- `public/fonts/GeistPixel.woff2` is [Geist Pixel](https://github.com/vercel/geist-pixel-font) by Vercel, under the SIL Open Font License.

## Credits

This site started from the [Astroship](https://github.com/surjithctly/astroship) template by Web3Templates, which is licensed under GPL-3.0. Its license is kept in [`LICENSE`](LICENSE) in this folder.
