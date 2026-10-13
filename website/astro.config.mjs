import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";
import icon from "astro-icon";

// Used for canonical and Open Graph URLs and the sitemap. SITE_URL wins; on Vercel the
// production domain is picked up automatically.
const site =
  process.env.SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : "https://crumbs.example.com");

export default defineConfig({
  site,
  integrations: [sitemap(), icon()],
  vite: {
    plugins: [tailwindcss()],
  },
});
