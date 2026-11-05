#!/bin/sh
# Install from this checkout. --copy is used by the remote installer.
set -eu

mode=link
case "${1-}" in
    "") ;;
    --copy) mode=copy ;;
    *) printf 'Usage: %s [--copy]\n' "$0" >&2; exit 1 ;;
esac
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config_dir="$HOME/.config/rex"

# Validate all sources before changing the installation.
for file in hatch.lua pick-project.sh select-session.sh init-snippet.lua default.rex-egg.lua; do
    [ -f "$source_dir/$file" ] || { printf 'Missing source: %s\n' "$file" >&2; exit 1; }
done
mkdir -p "$config_dir"
install_file() {
    source="$source_dir/$1"
    target="$config_dir/$2"
    if [ -d "$target" ]; then
        printf 'Refusing to replace directory: %s\n' "$target" >&2
        exit 1
    fi
    # Remove old links first so copy mode never writes through them.
    if [ -L "$target" ]; then rm "$target"; fi
    if [ "$mode" = link ]; then
        ln -sf "$source" "$target"
    else
        cp "$source" "$target"
    fi
}
install_file hatch.lua hatch.lua
install_file pick-project.sh pick-project.sh
install_file select-session.sh select-session.sh
install_file init-snippet.lua hatch-picker.lua
chmod +x "$config_dir/pick-project.sh" "$config_dir/select-session.sh"

# The default egg is always a copy, so users can customize it independently.
if [ ! -e "$config_dir/.rex-egg.lua" ] && [ ! -L "$config_dir/.rex-egg.lua" ]; then
    cp "$source_dir/default.rex-egg.lua" "$config_dir/.rex-egg.lua"
fi

registration='dofile(os.getenv("HOME") .. "/.config/rex/hatch-picker.lua")'
touch "$config_dir/init.lua"
if ! grep -Fqx "$registration" "$config_dir/init.lua"; then
    printf '\n-- Hatch project picker\n%s\n' "$registration" >> "$config_dir/init.lua"
fi

printf 'Installed Hatch in %s (%s mode).\n' "$config_dir" "$mode"
if command -v rex >/dev/null 2>&1; then
    rex config check
fi
printf 'Run: rex config reload\n'
