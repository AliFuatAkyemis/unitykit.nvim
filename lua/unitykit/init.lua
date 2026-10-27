-- Plugin entry point. `setup` merges the user options and registers the
-- nvim-cmp source exactly once per process.
local M = {}

local registered = false

---Applies user options and registers the cmp source the first time.
---Repeated calls only update the config. Works without nvim-cmp installed.
---@param opts table|nil
---@return unitykit.Config
function M.setup(opts)
  local cfg = require("unitykit.config").setup(opts)
  if not registered then
    require("unitykit.completion.cmp").register(cfg)
    registered = true
  end
  return cfg
end

return M
