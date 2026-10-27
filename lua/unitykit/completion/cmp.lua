-- nvim-cmp source for Unity message bodies.
-- `cmp` is optional and is only required inside `register`, so this module
-- loads fine under `-u NONE` or when nvim-cmp is not installed.
local config = require("unitykit.config")
local context = require("unitykit.context")
local item = require("unitykit.completion.item")
local messages = require("unitykit.messages")
local project = require("unitykit.project")

local M = {}

M.KEYWORD_PATTERN = [[\%([A-Za-z_][A-Za-z0-9_]*\)\?]]

---Collects completion items for a buffer, or `{}` when the cursor is not in a
---completion position. Guards run cheapest first.
---@param bufnr integer
---@param cfg table Resolved config.
---@return table[] items Raw cmp items.
function M.items(bufnr, cfg)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  cfg = cfg or config.get()

  if not vim.tbl_contains(cfg.filetypes, vim.bo[bufnr].filetype) then
    return {}
  end
  if vim.bo[bufnr].buftype ~= "" or not vim.bo[bufnr].modifiable then
    return {}
  end
  if project.root(bufnr) == nil then
    return {}
  end

  local ctx = context.resolve(bufnr, cfg)
  if ctx.class_kind == nil then
    return {}
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  if not context.is_in_class_body(ctx, row) then
    return {}
  end

  local implemented = ctx.implemented or {}
  local items = {}
  for _, msg in ipairs(messages.get(ctx.class_kind)) do
    if not (cfg.hide_implemented and implemented[msg.name]) then
      items[#items + 1] = item.to_cmp_item(msg, cfg, ctx)
    end
  end
  return items
end

---Reports whether the cursor directly follows a word character.
---@return boolean
function M.is_available()
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok then
    return false
  end
  local ok_line, line = pcall(vim.api.nvim_get_current_line)
  if not ok_line then
    return false
  end
  return line:sub(1, cursor[2]):match("[%w_]$") ~= nil
end

-- nvim-cmp invokes `source:complete(params, callback)`, so the callback is the
-- third argument; calling `source.complete(params, callback)` directly puts it
-- second. Both shapes are accepted.
local function complete_command(_, params, callback)
  if type(callback) ~= "function" then
    callback = params
  end
  local ok, collected = pcall(function()
    return M.items(vim.api.nvim_get_current_buf(), config.get())
  end)
  local items = {}
  if ok and type(collected) == "table" then
    items = collected
  end
  if type(callback) == "function" then
    callback({ items = items, isIncomplete = false })
  end
end

---cmp source table. `complete` never throws: a vanishing buffer yields `{}`.
M.source = {
  complete = complete_command,

  ---@return boolean
  is_available = function()
    return M.is_available()
  end,

  ---@return string[]
  get_trigger_characters = function()
    return {}
  end,

  -- cmp calls this callback with `:`; a plain `keyword_pattern` field is not read.
  ---@return string
  get_keyword_pattern = function(_)
    return M.KEYWORD_PATTERN
  end,
}

---Registers the source with nvim-cmp. Silently returns false when unavailable.
---Per-source priority is not a cmp source field: the user must configure it in
---`sources = { { name = "unitykit", priority = 1000 } }`.
---@param cfg table|nil Resolved config (kept for the call site in `init.setup`).
---@return boolean registered
function M.register(cfg) --luacheck: ignore cfg
  local ok, cmp = pcall(require, "cmp")
  if not ok or type(cmp) ~= "table" or type(cmp.register_source) ~= "function" then
    return false
  end
  return pcall(cmp.register_source, "unitykit", M.source)
end

return M
