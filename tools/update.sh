#!/usr/bin/env bash

repo=~/docs/

cd "$repo"
git pull origin main
bundle exec jekyll build
sudo rm -r /var/www/html/*
sudo cp -R _site/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
