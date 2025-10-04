#!/usr/bin/env bash

repo=~/docs/

cd "$repo"
git pull origin main
bundle exec jekyll build
sudo cp -R _site/* /var/www/html/
