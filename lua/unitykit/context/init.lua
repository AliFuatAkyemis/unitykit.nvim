-- Context orchestration: the regex fallback answers immediately on every call
-- and a valid LSP answer fills in the class kind asynchronously. Never blocks
-- the caller. The cache is keyed by class (name + start line) so moving the
-- cursor between nested or sibling classes without editing stays correct.
local cache = require("unitykit.context.cache")
local fallback = require("unitykit.context.fallback")
local project = require("unitykit.project")

local M = {}

local function current_tick(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local ok, tick = pcall(vim.api.nvim_buf_get_changedtick, bufnr)
  if ok then
    return tick
  end
  return nil
end

-- Dispatches one LSP resolution for a class key. The result is stored under
-- the class key captured here, so a late answer for a stale tick or a
-- different class never overwrites anything.
local function request_lsp(bufnr, cfg, class_key, class_name, class_start_line)
  local dispatch_tick = current_tick(bufnr)
  local ok, lsp = pcall(require, "unitykit.context.lsp")
  if not ok or type(lsp) ~= "table" or type(lsp.resolve) ~= "function" then
    return
  end
  -- Timeout and success may both fire; only the first answer counts.
  local finished = false
  lsp.resolve(bufnr, cfg, function(lsp_ctx)
    if finished then
      return
    end
    finished = true
    if not lsp_ctx or lsp_ctx.class_kind == nil then
      return
    end
    -- The buffer was edited during the round-trip: the answer is stale.
    if dispatch_tick == nil or current_tick(bufnr) ~= dispatch_tick then
      return
    end
    -- The request for this class was superseded or already answered.
    if not cache.pending(bufnr, class_key) then
      return
    end
    -- The language server selects the class from the cursor position when the
    -- response arrives, so an answer computed after the cursor moved belongs
    -- to another class. Storing it under the dispatch key would poison that
    -- class with a foreign kind; discard it and let the next resolve retry.
    local answer_range = lsp_ctx.class_range
    if
      lsp_ctx.class_name ~= class_name
      or type(answer_range) ~= "table"
      or answer_range.start_line ~= class_start_line
    then
      cache.clear_pending(bufnr, class_key)
      return
    end
    cache.store_kind(bufnr, class_key, lsp_ctx.class_kind)
  end)
end

---Resolves the context for a buffer. The fallback result is recomputed on
---every call so cursor movement is honoured; a previously resolved kind (from
---the language server) is attached under the current class key when known.
---@param bufnr integer|nil
---@param cfg table
---@return unitykit.Context
function M.resolve(bufnr, cfg)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local ctx = fallback.resolve(bufnr)
  if ctx.class_name == nil or ctx.class_range == nil then
    return ctx
  end

  local class_key = ctx.class_name .. ":" .. ctx.class_range.start_line
  local kind = cache.get_kind(bufnr, class_key)
  if kind ~= nil then
    ctx.class_kind = kind
    ctx.source = "lsp"
    return ctx
  end

  if not cache.pending(bufnr, class_key) then
    cache.set_pending(bufnr, ctx)
    request_lsp(bufnr, cfg, class_key, ctx.class_name, ctx.class_range.start_line)
  end
  return ctx
end

---Clears the cached context for one buffer, or for every buffer when nil.
---@param bufnr integer|nil
function M.invalidate(bufnr)
  cache.invalidate(bufnr)
end

---Reports whether a 0-based row is inside the class body but outside members.
---@param ctx unitykit.Context
---@param row integer 0-based line number
---@return boolean
function M.is_in_class_body(ctx, row)
  if type(ctx) ~= "table" or type(ctx.class_range) ~= "table" then
    return false
  end
  local range = ctx.class_range
  if type(row) ~= "number" or type(range.start_line) ~= "number" then
    return false
  end
  if row < range.start_line or row > (range.end_line or range.start_line) then
    return false
  end
  for _, method in ipairs(ctx.method_ranges or {}) do
    if row >= method.start_line and row <= method.end_line then
      return false
    end
  end
  return true
end

-- One augroup; `clear = true` keeps re-requiring the module from duplicating it.
local group = vim.api.nvim_create_augroup("unitykit_context", { clear = true })
vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
  group = group,
  callback = function(args)
    cache.invalidate(args.buf)
    project.reset(args.buf)
  end,
})

return M
