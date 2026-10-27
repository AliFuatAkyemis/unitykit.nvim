local M = {}

M.defaults = {
  filetypes = { "cs" },
  body = "block",
  access = "none",
  hide_implemented = true,
  priority = true,
  timeout_ms = 1500,
}

local valid_body = { block = true, line = true }
local valid_access = { none = true, private = true, public = true, protected = true }

function M.setup(opts)
  opts = opts or {}
  local cfg = vim.tbl_deep_extend("force", {}, M.defaults, opts)

  for key, whitelist in pairs({
    body = valid_body,
    access = valid_access,
  }) do
    if cfg[key] ~= nil and not whitelist[cfg[key]] then
      vim.notify(("unitykit: invalid %s %s, using default"):format(key, tostring(cfg[key])), vim.log.levels.WARN)
      cfg[key] = M.defaults[key]
    end
  end

  if type(cfg.timeout_ms) ~= "number" then
    cfg.timeout_ms = M.defaults.timeout_ms
  end

  cfg.filetypes = vim.list_extend({}, cfg.filetypes or M.defaults.filetypes)

  M.current = cfg
  return cfg
end

function M.get()
  return M.current or M.setup()
end

return M
