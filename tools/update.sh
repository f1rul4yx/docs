#!/usr/bin/env bash
repo=~/docs/

{
  echo "========== $(date) =========="
  cd "$repo" || exit 1
  git pull origin main

  which bundle
  ~/gems/bin/bundle exec ~/gems/bin/jekyll build 2>&1

  ls -l _site | head -n 10

  sudo rm -rf /var/www/html/*
  sudo cp -R _site/* /var/www/html/
  sudo chown -R www-data:www-data /var/www/html/
} >> ~/update.log 2>&1
