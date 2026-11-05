# hatch

Create a [Rex](https://www.superlogical.com/rex) session from a per-repo layout file.

- `hatch.lua`: the builder. `rex do hatch.lua dir=DIR` (optional `name=LABEL`).
- `.rex-egg.lua` in a repo: returns the session layout (see `example/`, schema in the header of `hatch.lua`).
- `pick-project.sh`: fzf picker; reuses the selected project's session or hatches a new one.
- `select-session.sh`: switches to the selected session.
- `init-snippet.lua`: adds **Hatch Project…** to the palette. Optionally bind with `rex.bind(KEY, "hatch_session_in")`.

## Install

Requires `rex`, `zsh`, and `jq`. Install `fzf` for fuzzy project selection; without it, Hatch uses the native macOS folder dialog (Finder).

```sh
mkdir -p ~/.config/rex
cp hatch.lua pick-project.sh select-session.sh ~/.config/rex/
chmod +x ~/.config/rex/pick-project.sh ~/.config/rex/select-session.sh
```

Paste `init-snippet.lua` into `~/.config/rex/init.lua`, then run `rex config check` and `rex config reload`.

## Usage

`PROJECT_PICKER` at the top of `pick-project.sh` sets the preferred picker: `fzf` (default) or `finder`. You can also set it in the environment, e.g. `PROJECT_PICKER=finder ~/.config/rex/pick-project.sh`. If fzf is unavailable, Hatch automatically falls back to Finder's folder dialog, which can choose any folder regardless of configured project roots.

Hatch Project launches the picker from a floating terminal pane; with fzf, Enter opens the project and Escape cancels. Canceling Finder also exits without creating a session. zsh loads `FZF_DEFAULT_OPTS` from `.zshenv`. The picker scans immediate, non-hidden subfolders of `~/Projects/personal` and `~/Projects/work`, falling back to `~/projects` when neither exists. Pass custom roots when running directly:

```sh
~/.config/rex/pick-project.sh ~/code ~/work
```

Picker-created sessions use the full `~/…` path as their label, overriding the layout's name so reopening finds the same session. Direct Hatch invocations still honor the configured name.

`.rex-egg.lua` is loaded with an empty environment, but its `cmd` strings run in a shell. Only hatch repos you trust.
