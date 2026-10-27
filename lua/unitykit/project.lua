local M = {}

-- Cache: { [bufnr]: { name = string, root = string|nil } }.
-- Kept self-consistent by comparing the cached buffer name on access,
-- so no autocmds are needed (the caller owning buffers clears via reset).
local cache = {}

-- Both an `Assets` directory and a readable
-- `ProjectSettings/ProjectVersion.txt` are required for a Unity root.
function M.is_unity_root(dir)
  return vim.fn.isdirectory(dir .. "/Assets") == 1
    and vim.fn.filereadable(dir .. "/ProjectSettings/ProjectVersion.txt") == 1
end

-- Walks up from the buffer's file (max 64 levels, stopping at `/`)
-- and returns the nearest Unity root directory, or nil when there is none.
function M.root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end

  local entry = cache[bufnr]
  if entry ~= nil and entry.name == name then
    return entry.root
  end

  local abs = vim.fs.dirname(vim.fs.normalize(name))
  local new_root
  for _ = 1, 64 do
    if M.is_unity_root(abs) then
      new_root = abs
      break
    end
    local parent = vim.fs.dirname(abs)
    if parent == abs then
      break -- reached `/`
    end
    abs = parent
  end

  cache[bufnr] = { name = name, root = new_root }
  return new_root
end

-- Clears one cached entry, or the whole cache when bufnr is nil.
function M.reset(bufnr)
  if bufnr == nil then
    cache = {}
  else
    cache[bufnr] = nil
  end
end

return M
