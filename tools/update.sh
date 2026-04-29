#!/usr/bin/env bash

export GEM_HOME="$HOME/gems"
export PATH="$HOME/gems/bin:$PATH"
repo=/opt/docs/

cd "$repo"

echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"

BEFORE=$(git rev-parse HEAD)
git pull origin main
AFTER=$(git rev-parse HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
    echo "No changes, skipping build"
    exit 0
fi

JEKYLL_ENV=production bundle exec jekyll build
rsync -av --delete _site/ /var/www/docs/
