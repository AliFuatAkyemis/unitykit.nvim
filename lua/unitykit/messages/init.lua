-- Bundled Unity message tables with a small read-only query API.
local M = {}

M.kinds = { "monobehaviour", "scriptableobject", "editor" }

M.sets = {
  monobehaviour = require("unitykit.messages.monobehaviour"),
  scriptableobject = require("unitykit.messages.scriptableobject"),
  editor = require("unitykit.messages.editor"),
}

-- Returns the bundled list for `kind`, or an empty table when unknown.
-- Callers treat the returned table as read-only.
function M.get(kind)
  return M.sets[kind] or {}
end

-- Linear scan: the lists are small and order is meaningful for completion.
function M.get_by_name(kind, name)
  for _, message in ipairs(M.get(kind)) do
    if message.name == name then
      return message
    end
  end
  return nil
end

return M
