#!/bin/sh
# Download a complete release into a temporary directory, then install copies.
set -eu

base_url="https://raw.githubusercontent.com/gcacoutinho/rex-hatch/main"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 1' HUP INT TERM

for file in install-local.sh hatch.lua pick-project.sh select-session.sh init-snippet.lua default.rex-egg.lua; do
    curl -fsSL "$base_url/$file" -o "$temp_dir/$file"
done
sh "$temp_dir/install-local.sh" --copy
