#!/usr/bin/env bash
repo=~/docs/
export GEM_HOME="$HOME/gems"
export PATH="$HOME/gems/bin:$PATH"

{
  echo "========== $(date) =========="
  cd "$repo" || exit 1
  git pull origin main

  which bundle
  bundle exec jekyll build 2>&1

  ls -l _site | head -n 10

  sudo rm -rf /var/www/html/*
  sudo cp -R _site/* /var/www/html/
  sudo chown -R www-data:www-data /var/www/html/
} >> ~/update.log 2>&1
