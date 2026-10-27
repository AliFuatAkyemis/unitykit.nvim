-- Plugin entry point. `setup` merges the user options and registers the
-- nvim-cmp source exactly once per process.
local M = {}

local registered = false

---Applies user options and registers the cmp source the first time it can.
---Repeated calls only update the config. Works without nvim-cmp installed: a
---later call retries registration once cmp becomes available.
---@param opts table|nil
---@return unitykit.Config
function M.setup(opts)
  local cfg = require("unitykit.config").setup(opts)
  if not registered then
    -- Only a real registration counts; `register` returns false when cmp is
    -- unavailable, so the next setup() call gets another chance.
    registered = require("unitykit.completion.cmp").register(cfg) == true
  end
  return cfg
end

return M
