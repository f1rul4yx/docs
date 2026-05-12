# AGENTS.md

This is a personal tech-blog Jekyll site (Chirpy theme ~> 7.3) for Spanish-language tutorials by Diego Vargas.

## Quick start

```bash
bundle install                          # install deps
bash tools/run.sh                       # dev server at http://127.0.0.1:4000 (live reload)
bash tools/test.sh                      # production build + html-proofer validation
bundle exec jekyll s -l                 # direct serve (no wrapper)
```

Post front matter: `title`, `date`, `categories`, `tags`. Layout defaults to `post` via `_config.yml`.

## Structure

| Path | Purpose |
|---|---|
| `_posts/YYYY-MM-DD-title.md` | Blog posts (Spanish) |
| `_tabs/*.md` | Static pages (about, archives, categories, tags) with `icon` + `order` in front matter |
| `assets/img/capturas/` | Screenshots referenced in posts |
| `tools/run.sh` | Dev server wrapper |
| `tools/test.sh` | Build + html-proofer |
| `tools/update.sh` | Production deploy script |
| `Gemfile` | Ruby dependencies (no package.json — pure Jekyll) |

## Deployment

Cron-driven every 5 minutes via `tools/update.sh`: `git pull origin main` → `JEKYLL_ENV=production bundle exec jekyll build` → `rsync _site/` to `/var/www/docs/`.

No CI workflows. `Gemfile.lock` is gitignored (standard Jekyll practice).
