-- rex do ~/.config/rex/hatch.lua dir=DIR
-- Create a Rex session using DIR/.rex-egg.lua, falling back to
-- ~/.config/rex/.rex-egg.lua when absent. The layout file returns:
--
--   return {
--     name = "myrepo",                    -- session label (default: dir name)
--     windows = {                         -- windows are Rex's tabs
--       { name = "code", split = "right", ratio = 40, panes = {
--         { cmd = "nvim" },
--         { split = "below", panes = { { cmd = "npm run dev" }, {} } },
--       }},
--       { name = "agent", cmd = "claude" },
--     },
--   }
--
-- A node is a pane (cmd?, cwd?) or a container (panes, split?, ratio?).
-- split: right | below | left | above (default right); ratio: % for the second pane.
-- Containers take exactly two nodes; nest for more.

local function rex_cli(args)
  local argv = { "rex" }
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  local r = rex.exec(argv)
  if not r or not r.ok then
    error(table.concat(argv, " ") .. ": " .. (r and r.stderr or "failed to run"), 0)
  end
  return r.stdout
end

local function rexj(args)
  -- --json must precede any `--` COMMAND
  local pos = #args + 1
  for i, a in ipairs(args) do
    if a == "--" then pos = i; break end
  end
  table.insert(args, pos, "--json")
  return rex.json.decode(rex_cli(args))
end

local function first_leaf(node)
  if node.panes then return first_leaf(node.panes[1]) end
  return node
end

local function term_args(leaf, root)
  local cwd = leaf.cwd or "."
  if cwd:sub(1, 1) ~= "/" then cwd = root .. "/" .. cwd end
  local args = { "-c", cwd }
  if leaf.cmd then
    for _, a in ipairs({ "--", "sh", "-c", leaf.cmd }) do args[#args + 1] = a end
  end
  return args
end

local function cat(...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for _, v in ipairs(t) do out[#out + 1] = v end
  end
  return out
end

local function build(node, block, sid, root)
  local kids = node.panes
  if not kids then return end
  if #kids ~= 2 then
    error("panes must have exactly 2 nodes (got " .. #kids .. ")", 0)
  end
  local res = rexj(cat({
    "split", "-s", sid, "-b", block, "--split", node.split or "right",
    "--ratio", tostring(node.ratio or 50), "--focus=false",
  }, term_args(first_leaf(kids[2]), root)))
  build(kids[1], block, sid, root)
  build(kids[2], res.block_ids[1], sid, root)
end

local root = (rex.args.dir or "."):gsub("/+$", "")
if root:sub(1, 1) ~= "/" then root = os.getenv("PWD") .. "/" .. root end

local cfg = {}
local file = root .. "/.rex-egg.lua"
local handle = io.open(file, "r")
if not handle then
  file = os.getenv("HOME") .. "/.config/rex/.rex-egg.lua"
  handle = io.open(file, "r")
end
if handle then
  handle:close()
  local chunk, err = loadfile(file)
  if not chunk then error(err, 0) end
  setfenv(chunk, {}) -- config is data only: no rex, io, os
  cfg = chunk() or {}
end

local name = rex.args.name or cfg.name or root:match("[^/]+$")
local wins = cfg.windows or {}
local sid

if #wins == 0 then
  sid = rexj({ "new", name, "-c", root }).session_id
else
  local w = wins[1]
  local s = rexj(cat({ "new", name, "--window", w.name or "main" }, term_args(first_leaf(w), root)))
  sid = s.session_id
  build(w, s.initial_windows[1].block_ids[1], sid, root)
  for i = 2, #wins do
    local w2 = wins[i]
    local r = rexj(cat(
      { "window", "new", w2.name or "window", "-s", sid, "--focus=false" },
      term_args(first_leaf(w2), root)))
    build(w2, r.block_ids[1], sid, root)
  end
end

-- unverified: switch the app to the new session, on its first window
rex.exec({ "rex", "focus", "-s", sid, "1" })
rex.exec({ "rex", "do", "session.select", "session_id=" .. sid })
return sid
