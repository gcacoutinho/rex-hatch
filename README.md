# hatch

Create a [Rex](https://www.superlogical.com/rex) session from a per-repo layout file.

- `hatch.lua`: the builder. `rex do ~/.config/rex/hatch.lua dir=DIR` (optional `name=LABEL`).
- `.rex-egg.lua` in a repo: returns the session layout (see `example/`, schema in the header of `hatch.lua`).
- `~/.config/rex/.rex-egg.lua`: fallback layout when the project has no layout file. `default.rex-egg.lua` provides a single shell tab; customize it to set your default.
- `pick-project.sh`: fzf picker; reuses the selected project's session or hatches a new one.
- `select-session.sh`: switches to the selected session.
- `init-snippet.lua`: adds **Hatch Project…** to the palette. Optionally bind with `rex.bind(KEY, "hatch_session_in")`.

## Install

Requires `rex`, `zsh`, and `jq`. Install `fzf` for fuzzy project selection; without it, Hatch uses the native macOS folder dialog (Finder), which requires macOS and `osascript`. All methods install into `~/.config/rex/`.

### 1. Install from source (curl)

Download and run the installer (requires `curl`):

```sh
curl -fsSL https://raw.githubusercontent.com/gcacoutinho/rex-hatch/main/install.sh -o /tmp/rex-hatch-install.sh
# Review the script before running it.
sh /tmp/rex-hatch-install.sh
rex config reload
```

This downloads the source files from the repository's `main` branch and installs **copies**. Run it again to update the scripts.

### 2. Install from a repository checkout (symlinks)

```sh
git clone https://github.com/gcacoutinho/rex-hatch.git
cd rex-hatch
sh install-local.sh
rex config reload
```

This **symlinks** the builder, picker, session helper, and action into your Rex folder. Keep the checkout in place; edits and `git pull` update the installed scripts. Reload the config after changing the action.

Both installers **copy** the default egg only if `~/.config/rex/.rex-egg.lua` is absent, preserving any existing layout. They register the action in `init.lua` without replacing your config, skip an already-present registration line, and run `rex config check` when Rex is available.

### 3. Install manually

Create the destination directory:

```sh
mkdir -p ~/.config/rex
```

Then copy these files from the repository:

| Source | Destination |
| --- | --- |
| `hatch.lua` | `~/.config/rex/hatch.lua` |
| `pick-project.sh` | `~/.config/rex/pick-project.sh` |
| `select-session.sh` | `~/.config/rex/select-session.sh` |
| `init-snippet.lua` | `~/.config/rex/hatch-picker.lua` |
| `default.rex-egg.lua` | `~/.config/rex/.rex-egg.lua` (only if absent) |

After copying, make both shell scripts executable:

```sh
chmod +x ~/.config/rex/pick-project.sh ~/.config/rex/select-session.sh
```

Add this once to `~/.config/rex/init.lua` (create it if necessary):

```lua
dofile(os.getenv("HOME") .. "/.config/rex/hatch-picker.lua")
```

Alternatively, paste the contents of `init-snippet.lua` into `init.lua` instead of loading `hatch-picker.lua`. Do not register the action both ways.

Then validate and reload:

```sh
rex config check
rex config reload
```

## Usage

Open Rex's command palette and select **Hatch Project…**, then choose a project. Hatch reuses its session if one exists; otherwise, it creates one using the project's layout or your default layout.

To create a session directly without the picker:

```sh
rex do ~/.config/rex/hatch.lua dir=/path/to/project
# Optionally override the session label:
rex do ~/.config/rex/hatch.lua dir=/path/to/project name=my-project
```

Direct invocations create a new session rather than reusing one.

### Project selection

`PROJECT_PICKER` at the top of `pick-project.sh` sets the preferred picker: `fzf` (default) or `finder`. You can also set it in the environment, e.g. `PROJECT_PICKER=finder ~/.config/rex/pick-project.sh`. If fzf is unavailable, Hatch automatically falls back to Finder's folder dialog, which can choose any folder regardless of configured project roots.

Hatch Project launches the picker from a floating terminal pane; with fzf, Enter opens the project and Escape cancels. Canceling Finder also exits without creating a session. zsh loads `FZF_DEFAULT_OPTS` from `.zshenv`. The picker uses your home directory (`~` / `$HOME`) as its default base, scanning its immediate, non-hidden subfolders. Pass custom roots when running directly:

```sh
~/.config/rex/pick-project.sh ~/code ~/work
```

Picker-created sessions use the full project path as their label (`~/…` under your home directory, absolute paths elsewhere), overriding the layout's name so reopening finds the same session. Direct Hatch invocations still honor the configured name unless `name=LABEL` is supplied.

### Layouts

Create `.rex-egg.lua` in your project, for example:

```lua
return {
  windows = {
    { name = "dev", split = "right", ratio = 40, panes = {
      { cmd = "npm run dev" },
      {}, -- interactive shell
    } },
    { name = "shell" },
  },
}
```

- `windows` are Rex tabs; each entry is a pane or a split container.
- A pane's optional `cmd` runs through `sh -c`; omit it for an interactive shell. Its optional `cwd` is relative to the project directory unless absolute.
- Containers require exactly two entries in `panes`; nest containers for more panes.
- `split` is `right` (default), `below`, `left`, or `above`. `ratio` is the percentage given to the second pane, from 1 to 99 (default 50).
- The optional top-level `name` sets the session label for direct invocations; otherwise, the project directory name is used.

Hatch validates the full layout before creating a session. Without a project layout, it uses `~/.config/rex/.rex-egg.lua`; without either file, it creates a single shell tab. See [`example/.rex-egg.lua`](example/.rex-egg.lua) for a larger layout.

`.rex-egg.lua` is loaded with an empty environment, but its `cmd` strings run in a shell. Only hatch repos you trust.

## Tests

Requires Python 3, LuaJIT (`luajit`), `zsh`, and `jq`:

```sh
python3 -m unittest discover -s tests -v
sh -n install.sh install-local.sh
zsh -n pick-project.sh select-session.sh
```

Tests cover layout validation, nested layouts, session errors, picker cancellation and failures, session reuse, and installer copy/symlink behavior. Rex calls are mocked; tests do not change live Rex sessions.
