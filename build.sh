#!/usr/bin/env bash
# Render build script for posbd (Phoenix release)
set -o errexit

mix deps.get --only prod
MIX_ENV=prod mix compile

# Download tailwind/esbuild binaries and build minified, digested assets
MIX_ENV=prod mix assets.setup
MIX_ENV=prod mix assets.deploy

MIX_ENV=prod mix release --overwrite
