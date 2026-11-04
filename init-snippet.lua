-- Add to ~/.config/rex/init.lua, with hatch.lua at ~/.config/rex/hatch.lua
-- osascript blocks past the 30s action limit, so the whole flow runs detached
rex.action({
  name = "hatch_session_in",
  title = "Hatch Session in Folder…",
  category = "Sessions",
  run = function()
    rex.exec.start({ "sh", "-c", [[
      dir=$(osascript -e 'POSIX path of (choose folder with prompt "Hatch Rex session in:" default location (path to home folder))') || exit 0
      dir=${dir%/}
      rex do "$HOME/.config/rex/hatch.lua" dir="$dir"
    ]] }, { detach = true })
  end,
})
rex.bind("ctrl+b>f", "hatch_session_in")
