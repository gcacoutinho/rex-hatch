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

local root = rex.args.dir or "."
if root == "" then error("dir must not be empty", 0) end
root = root:gsub("/+$", "")
if root == "" then root = "/" end
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

-- Validate the entire layout before creating any sessions or panes.
local function require_type(value, expected, path)
  if type(value) ~= expected then error(path .. " must be a " .. expected, 0) end
end

local function optional_string(value, path)
  if value ~= nil then require_type(value, "string", path) end
end

local function array_length(value, path)
  require_type(value, "table", path)
  local n = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      error(path .. " must be an array", 0)
    end
    n = n + 1
  end
  for i = 1, n do
    if value[i] == nil then error(path .. " must not contain holes", 0) end
  end
  return n
end

local visiting = {}
local function validate_node(node, path)
  require_type(node, "table", path)
  if visiting[node] then error(path .. " contains a cycle", 0) end
  visiting[node] = true
  optional_string(node.name, path .. ".name")
  optional_string(node.cmd, path .. ".cmd")
  optional_string(node.cwd, path .. ".cwd")
  if node.panes ~= nil then
    if array_length(node.panes, path .. ".panes") ~= 2 then
      error(path .. ".panes must have exactly 2 nodes", 0)
    end
    if node.split ~= nil and node.split ~= "right" and node.split ~= "below"
        and node.split ~= "left" and node.split ~= "above" then
      error(path .. ".split must be right, below, left, or above", 0)
    end
    if node.ratio ~= nil then
      require_type(node.ratio, "number", path .. ".ratio")
      if not (node.ratio >= 1 and node.ratio <= 99) then
        error(path .. ".ratio must be between 1 and 99", 0)
      end
    end
    for i = 1, 2 do validate_node(node.panes[i], path .. ".panes[" .. i .. "]") end
  end
  visiting[node] = nil
end

require_type(cfg, "table", "layout")
optional_string(cfg.name, "layout.name")
local name = rex.args.name or cfg.name or root:match("[^/]+$") or "/"
optional_string(name, "session name")
local wins = cfg.windows
if wins == nil then wins = {} end
local count = array_length(wins, "layout.windows")
for i = 1, count do validate_node(wins[i], "layout.windows[" .. i .. "]") end
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

-- Switch the app to the new session, on its first window.
rex_cli({ "focus", "-s", sid, "1" })
rex_cli({ "do", "session.select", "session_id=" .. sid })
return sid
