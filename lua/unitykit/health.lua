-- `:checkhealth unitykit` support. Every section degrades gracefully: no
-- cmp, no LSP and no Unity root are reported, never raised. The check is
-- read-only: it never resolves context or sends LSP requests.
local config = require("unitykit.config")
local project = require("unitykit.project")

local M = {}

local MIN_VERSION = "0.10"

local function nvim_version()
  local version = vim.version()
  return ("%d.%d.%d"):format(version.major, version.minor, version.patch)
end

-- Names of the clients attached to the buffer that serve C# files.
local function csharp_clients(bufnr)
  local names = {}
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
  if not ok or type(clients) ~= "table" then
    return names
  end
  for _, client in ipairs(clients) do
    local filetypes = type(client.config) == "table" and client.config.filetypes or {}
    if vim.tbl_contains(filetypes, "cs") then
      names[#names + 1] = client.name
    end
  end
  return names
end

-- `:checkhealth` switches to its own buffer, so the buffer the user was in is
-- only reachable through the alternate buffer.
local function target_bufnr()
  local current = vim.api.nvim_get_current_buf()
  local is_health = vim.api.nvim_buf_get_name(current):match("^health://") ~= nil
    or vim.bo[current].filetype == "checkhealth"
  if not is_health then
    return current
  end
  local alternate = vim.fn.bufnr("#")
  if alternate ~= -1 and vim.api.nvim_buf_is_valid(alternate) then
    return alternate
  end
  return current
end

local function check_version()
  local version = nvim_version()
  if vim.fn.has("nvim-" .. MIN_VERSION) == 1 then
    vim.health.ok(("Neovim %s (>= %s)"):format(version, MIN_VERSION))
  else
    vim.health.error(("Neovim %s is too old, >= %s is required"):format(version, MIN_VERSION))
  end
end

local function check_cmp()
  -- Read-only presence probe; delegates to completion/cmp.lua so this module
  -- never touches `require("cmp")` directly.
  if require("unitykit.completion.cmp").is_available() then
    vim.health.ok("nvim-cmp is installed")
    return true
  end
  vim.health.warn("nvim-cmp is not installed; the unitykit source cannot be registered")
  return false
end

local function check_source(cmp_available)
  if not cmp_available then
    vim.health.warn("Source: not registered, nvim-cmp is not installed")
    return
  end
  if require("unitykit").is_registered() then
    vim.health.ok("Source: unitykit is registered")
  else
    vim.health.error(
      "Source: unitykit is not registered; re-run require('unitykit').setup()"
    )
  end
end

local function check_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  vim.health.info("Current buffer: " .. (name ~= "" and name or "[No Name]"))

  local root = project.root(bufnr)
  if root then
    vim.health.ok("Unity project root: " .. root)
  else
    vim.health.info("Not a Unity project (no Assets/ and ProjectSettings/ProjectVersion.txt)")
  end

  local clients = csharp_clients(bufnr)
  if #clients > 0 then
    vim.health.ok("C# LSP: " .. table.concat(clients, ", "))
  elseif vim.tbl_contains(config.get().filetypes, vim.bo[bufnr].filetype) then
    vim.health.info("No C# LSP client (fallback active)")
  else
    vim.health.info("Not a C# buffer (no C# LSP client expected)")
  end

  return root
end

local function check_context(bufnr, root)
  if not root then
    vim.health.info("Context: skipped, the buffer is not inside a Unity project")
    return
  end

  -- Read-only: a cached entry exists only after completion resolved it. Never
  -- call context.resolve here, since that would fire an LSP request.
  local cached = require("unitykit.context.cache").get(bufnr)
  if type(cached) ~= "table" then
    vim.health.info("Context: not resolved yet (use completion in a C# buffer)")
    return
  end

  if cached.source then
    vim.health.ok("Context source: " .. tostring(cached.source))
  else
    vim.health.warn("Context source: unresolved")
  end

  if cached.class_kind then
    vim.health.ok(("Class: %s (%s)"):format(tostring(cached.class_name or "?"), cached.class_kind))
  else
    vim.health.info("Class: the cursor is not inside a recognised Unity class")
  end
end

---Runs every health check. Called by `:checkhealth unitykit`.
function M.check()
  vim.health.start("unitykit")
  check_version()
  local cmp_available = check_cmp()
  check_source(cmp_available)

  local bufnr = target_bufnr()
  local root = check_buffer(bufnr)
  check_context(bufnr, root)
end

return M
