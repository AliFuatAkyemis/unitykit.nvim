-- Changedtick-keyed cache for resolved class kinds.
-- Each buffer holds one entry per changedtick; inside it, `kinds` maps a
-- class key (`class_name .. ":" .. class_range.start_line`) to its resolved
-- message kind. Cursor moves between classes therefore stay correct without
-- an edit: a new class key is simply not in `kinds` yet. Any edit discards
-- the whole entry, since the changedtick no longer matches.
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

-- Returns the entry only while its tick still matches the buffer; otherwise
-- the stale entry is dropped and nil is returned.
local function fresh_entry(bufnr)
  local entry = M.entries[bufnr]
  if entry == nil then
    return nil
  end
  local tick = current_tick(bufnr)
  if tick == nil or entry.tick ~= tick then
    M.entries[bufnr] = nil
    return nil
  end
  return entry
end

-- Derives the class key from a context, or nil when the context does not
-- identify a class.
local function class_key_of(ctx)
  if type(ctx) ~= "table" then
    return nil
  end
  local name = ctx.class_name
  local range = ctx.class_range
  if type(name) ~= "string" or type(range) ~= "table" or type(range.start_line) ~= "number" then
    return nil
  end
  return name .. ":" .. range.start_line
end

-- Creates (or replaces, when the tick changed) the entry for a buffer.
local function ensure_entry(bufnr)
  local tick = current_tick(bufnr)
  if tick == nil then
    return nil
  end
  local entry = M.entries[bufnr]
  if entry == nil or entry.tick ~= tick then
    entry = { tick = tick, kinds = {}, pending = {}, last = nil }
    M.entries[bufnr] = entry
  end
  return entry
end

---Returns the most recently stored context for the buffer, or nil when the
---record is stale. Kept for the health check's read-only diagnostics.
---@param bufnr integer
---@return unitykit.Context|nil
function M.get(bufnr)
  local entry = fresh_entry(bufnr)
  if entry == nil then
    return nil
  end
  return entry.last
end

---Returns the resolved message kind for one class key, or nil when unknown.
---@param bufnr integer
---@param class_key string
---@return string|nil
function M.get_kind(bufnr, class_key)
  local entry = fresh_entry(bufnr)
  if entry == nil or type(class_key) ~= "string" then
    return nil
  end
  return entry.kinds[class_key]
end

---Stores a final context at the buffer's current changedtick, recording its
---kind under the context's class key.
---@param bufnr integer
---@param ctx unitykit.Context
---@return boolean
function M.set(bufnr, ctx)
  if type(bufnr) ~= "number" or type(ctx) ~= "table" then
    return false
  end
  local entry = ensure_entry(bufnr)
  if entry == nil then
    return false
  end
  local key = class_key_of(ctx)
  if key and ctx.class_kind ~= nil then
    entry.kinds[key] = ctx.class_kind
    entry.pending[key] = nil
  end
  entry.last = ctx
  return true
end

---Stores a provisional (fallback) context and marks its class key as having a
---language-server request in flight.
---@param bufnr integer
---@param ctx unitykit.Context
---@return boolean
function M.set_pending(bufnr, ctx)
  if type(bufnr) ~= "number" or type(ctx) ~= "table" then
    return false
  end
  local entry = ensure_entry(bufnr)
  if entry == nil then
    return false
  end
  local key = class_key_of(ctx)
  if key then
    entry.pending[key] = true
  end
  entry.last = ctx
  return true
end

---Reports whether a request is in flight: for a specific class key when given,
---otherwise for any class key in the buffer.
---@param bufnr integer
---@param class_key string|nil
---@return boolean
function M.pending(bufnr, class_key)
  local entry = fresh_entry(bufnr)
  if entry == nil then
    return false
  end
  if class_key ~= nil then
    return entry.pending[class_key] == true
  end
  for _ in pairs(entry.pending) do
    return true
  end
  return false
end

---Records a resolved kind under a specific class key and clears its pending
---flag. No-op when the buffer tick moved on since the request was dispatched.
---@param bufnr integer
---@param class_key string
---@param kind string
---@return boolean
function M.store_kind(bufnr, class_key, kind)
  local entry = fresh_entry(bufnr)
  if entry == nil or type(class_key) ~= "string" then
    return false
  end
  entry.kinds[class_key] = kind
  entry.pending[class_key] = nil
  -- Reflect the resolution for read-only diagnostics without mutating the
  -- context object a caller already holds (a synchronous answer would
  -- otherwise rewrite the fallback context that was just returned).
  if entry.last and class_key_of(entry.last) == class_key then
    entry.last = vim.tbl_extend("force", {}, entry.last, {
      class_kind = kind,
      source = "lsp",
    })
  end
  return true
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
