# hatch

Create a [Rex](https://www.superlogical.com/rex) session from a per-repo layout file.

- `hatch.lua`: the builder. `rex do hatch.lua dir=DIR`
- `.rex-egg.lua` in a repo: returns the session layout (see `example/`, schema in the header of `hatch.lua`)
- `init-snippet.lua`: a "Hatch Session in Folder…" action with a macOS folder picker (`osascript`)

Install: put `hatch.lua` at `~/.config/rex/hatch.lua`, paste the snippet into `init.lua`, run `rex config reload`.

`.rex-egg.lua` is loaded with an empty environment, but its `cmd` strings run in a shell. Only hatch repos you trust.
