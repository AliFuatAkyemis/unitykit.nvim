-- Context orchestration: the regex fallback answers immediately and a valid
-- LSP answer replaces it asynchronously. Never blocks the caller.
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

local function request_lsp(bufnr, cfg, pending_tick)
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
    if pending_tick == nil or current_tick(bufnr) ~= pending_tick then
      return
    end
    -- The entry was replaced or invalidated meanwhile.
    if not cache.pending(bufnr) then
      return
    end
    cache.set(bufnr, lsp_ctx)
  end)
end

---Resolves the context for a buffer, returning the fallback immediately.
---@param bufnr integer|nil
---@param cfg table
---@return unitykit.Context
function M.resolve(bufnr, cfg)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local cached = cache.get(bufnr)
  if cached then
    return cached
  end

  local ctx = fallback.resolve(bufnr)
  cache.set_pending(bufnr, ctx)
  request_lsp(bufnr, cfg, current_tick(bufnr))
  return ctx
end

---Clears the cached context for one buffer, or for every buffer when nil.
---@param bufnr integer|nil
function M.invalidate(bufnr)
  cache.invalidate(bufnr)
end

---Reports whether a 0-based row is inside the class body but outside methods.
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
