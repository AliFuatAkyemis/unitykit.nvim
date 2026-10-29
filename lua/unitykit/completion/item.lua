--- Render Unity messages as LSP snippets and cmp completion items.
local M = {}

M.KIND_SNIPPET = 15
M.FORMAT_SNIPPET = 2

M.ACCESS = {
  none = "",
  private = "private ",
  public = "public ",
  protected = "protected ",
}

--- Build the C# signature line for a message.
---@param msg table Message (name, modifiers, returns, params).
---@param cfg table Resolved config (access).
---@return string signature
function M.signature(msg, cfg)
  local access = msg.modifiers and (msg.modifiers .. " ") or M.ACCESS[cfg.access] or ""
  local ret = msg.returns and (msg.returns .. " ") or "void "
  return access .. ret .. msg.name .. "(" .. (msg.params or "") .. ")"
end

--- Render the LSP snippet text for a message.
---@param msg table Message.
---@param cfg table Resolved config (body).
---@return string snippet Snippet text including $0.
function M.render(msg, cfg)
  local sig = M.signature(msg, cfg)
  if cfg.body == "line" then
    return sig .. " { $0 }"
  end
  return sig .. "\n{\n    $0\n}"
end

--- Render a message as an nvim-cmp item entry.
---@param msg table Message.
---@param cfg table Resolved config.
---@param ctx table|nil Resolved Context (unused here; Task 8 consumes it).
---@return table cmp_item
function M.to_cmp_item(msg, cfg, ctx) --luacheck: ignore ctx
  local sig = M.signature(msg, cfg)
  return {
    word = msg.name,
    label = msg.name .. "()",
    kind = M.KIND_SNIPPET,
    insertTextFormat = M.FORMAT_SNIPPET,
    insertText = M.render(msg, cfg),
    detail = "Unity Message",
    documentation = {
      kind = "markdown",
      value = table.concat({
        "**" .. msg.name .. "** — " .. msg.doc,
        "",
        "```csharp",
        sig,
        "```",
      }, "\n"),
    },
    sortText = cfg.priority and ("0" .. msg.name) or nil,
    filterText = msg.name,
    preselect = true,
  }
end

return M
