#!/usr/bin/env bash

export GEM_HOME="$HOME/gems"
export PATH="$HOME/gems/bin:$PATH"
repo=~/docs/

cd "$repo"

BEFORE=$(git rev-parse HEAD)
git pull origin main
AFTER=$(git rev-parse HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
    echo "No changes, skipping build"
    exit 0
fi

JEKYLL_ENV=production bundle exec jekyll build
sudo rsync -av --delete _site/ /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
