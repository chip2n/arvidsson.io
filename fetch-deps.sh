#!/usr/bin/env bash

set -e

mkdir -p public/static

# Fetch the latest version of zball
wget https://github.com/chip2n/zball/releases/latest/download/game.wasm -O public/static/game.wasm
wget https://github.com/chip2n/zball/releases/latest/download/game.js -O public/static/game.js
