-- Changedtick-keyed cache for resolved contexts.
-- A record is fresh only while the buffer's changedtick matches the tick
-- captured when it was stored, so any edit discards the whole entry.
local M = {}

M.entries = {}

-- Returns the current changedtick, or nil for invalid buffers.
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

local function store(bufnr, ctx, pending)
  if type(bufnr) ~= "number" or type(ctx) ~= "table" then
    return false
  end
  local tick = current_tick(bufnr)
  if tick == nil then
    return false
  end
  M.entries[bufnr] = { tick = tick, ctx = ctx, pending = pending }
  return true
end

---Returns the cached context when the record is still fresh.
---@param bufnr integer
---@return unitykit.Context|nil
function M.get(bufnr)
  local entry = M.entries[bufnr]
  if entry == nil then
    return nil
  end
  local tick = current_tick(bufnr)
  if tick == nil or entry.tick ~= tick then
    M.entries[bufnr] = nil
    return nil
  end
  return entry.ctx
end

---Stores a final context at the buffer's current changedtick.
---@param bufnr integer
---@param ctx unitykit.Context
---@return boolean
function M.set(bufnr, ctx)
  return store(bufnr, ctx, false)
end

---Stores a provisional (fallback) context while the LSP answer is pending.
---@param bufnr integer
---@param ctx unitykit.Context
---@return boolean
function M.set_pending(bufnr, ctx)
  return store(bufnr, ctx, true)
end

---Reports whether a fresh record still awaits its final value.
---@param bufnr integer
---@return boolean
function M.pending(bufnr)
  local entry = M.entries[bufnr]
  if entry == nil then
    return false
  end
  local tick = current_tick(bufnr)
  if tick == nil or entry.tick ~= tick then
    M.entries[bufnr] = nil
    return false
  end
  return entry.pending == true
end

---Clears one buffer's record, or every record when bufnr is nil.
---@param bufnr integer|nil
function M.invalidate(bufnr)
  if bufnr == nil then
    M.entries = {}
  else
    M.entries[bufnr] = nil
  end
end

return M
