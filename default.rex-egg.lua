-- Fallback layout for projects without their own .rex-egg.lua.
-- All panes start in the selected project folder unless cwd is specified.
-- Omit name so the session label comes from the selected project.
return {
  windows = {
    { name = "shell" },
  },
}
