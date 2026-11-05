-- Install hatch.lua, pick-project.sh and select-session.sh in ~/.config/rex/.
-- fzf needs a TTY: launch it in a floating terminal pane.
rex.action({
  name = "hatch_session_in",
  title = "Hatch Project…",
  category = "Sessions",
  run = function()
    local result, err = rex.session.new_layer({
      bounds = { 0.15, 0.15, 0.7, 0.7 },
      focus = true,
      layout = rex.layout.block({
        flavor = "com.superlogical.terminal.shell",
        options = {
          command = { "/bin/zsh", os.getenv("HOME") .. "/.config/rex/pick-project.sh" },
        },
      }),
    })
    if not result then error(err or "Failed to open project picker", 0) end
    return result
  end,
})
