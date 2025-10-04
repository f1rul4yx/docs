#!/usr/bin/env bash

export GEM_HOME="$HOME/gems"
export PATH="$HOME/gems/bin:$PATH"
repo=~/docs/

cd "$repo"
git pull origin main
bundle exec jekyll build
sudo rsync -av --delete _site/ /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
