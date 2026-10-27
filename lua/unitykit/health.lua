-- `:checkhealth unitykit` support. Every section degrades gracefully: no
-- cmp, no LSP and no Unity root are reported, never raised.
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
  if pcall(require, "cmp") then
    vim.health.ok("nvim-cmp is installed")
  else
    vim.health.warn("nvim-cmp is not installed; the unitykit source stays unregistered")
  end
end

local function check_source()
  if package.loaded["unitykit.completion.cmp"] then
    vim.health.ok("unitykit source module is loaded")
  else
    vim.health.warn("unitykit source is not loaded; call require('unitykit').setup()")
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
  else
    vim.health.info("No C# LSP client (fallback active)")
  end

  return root
end

local function check_context(bufnr, root)
  local cfg = config.get()
  local filetype = vim.bo[bufnr].filetype
  if not root then
    vim.health.info("Context: skipped, the buffer is not inside a Unity project")
    return
  end
  if not vim.tbl_contains(cfg.filetypes, filetype) then
    vim.health.info(("Context: skipped, filetype %q is not in config.filetypes"):format(filetype))
    return
  end

  local ok, ctx = pcall(require("unitykit.context").resolve, bufnr, cfg)
  if not ok or type(ctx) ~= "table" then
    vim.health.error("Context: resolution failed")
    return
  end

  if ctx.source then
    vim.health.ok("Context source: " .. tostring(ctx.source))
  else
    vim.health.warn("Context source: unresolved")
  end

  if ctx.class_kind then
    vim.health.ok(("Class: %s (%s)"):format(tostring(ctx.class_name or "?"), ctx.class_kind))
  else
    vim.health.info("Class: the cursor is not inside a recognised Unity class")
  end
end

---Runs every health check. Called by `:checkhealth unitykit`.
function M.check()
  vim.health.start("unitykit")
  check_version()
  check_cmp()
  check_source()

  local bufnr = target_bufnr()
  local root = check_buffer(bufnr)
  check_context(bufnr, root)
end

return M
