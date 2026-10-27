-- LSP-based context resolution: document symbols for the class and its
-- methods, then the base class chain via hover and workspace symbols.
-- Line numbers are 0-based and `class_range.end_line` is inclusive.
local fallback = require("unitykit.context.fallback")

local M = {}

local CLASS_KIND = 5
local METHOD_KIND = 6
local MAX_DEPTH = 8
local DEFAULT_TIMEOUT = 1500

local KIND_BY_QUALIFIED = {
  ["UnityEngine.MonoBehaviour"] = "monobehaviour",
  ["UnityEngine.ScriptableObject"] = "scriptableobject",
  ["UnityEditor.Editor"] = "editor",
}

local QUALIFIED_BY_KIND = {}
for qualified, kind in pairs(KIND_BY_QUALIFIED) do
  QUALIFIED_BY_KIND[kind] = qualified
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Maps a message kind to its fully qualified Unity type name.
---@param kind string|nil
---@return string|nil
function M.qualify(kind)
  if type(kind) ~= "string" then
    return nil
  end
  return QUALIFIED_BY_KIND[kind]
end

---Removes a generic argument list and trims the result.
---@param name string|nil
---@return string
function M.strip_generics(name)
  if type(name) ~= "string" then
    return ""
  end
  local generic = name:find("<", 1, true)
  if generic then
    name = name:sub(1, generic - 1)
  end
  return trim(name)
end

-- Splits a base list on commas, but only outside generic argument lists, so
-- `Base<int, string>` stays one entry.
local function split_base_list(text)
  local parts = {}
  local start = 1
  local depth = 0
  for index = 1, #text do
    local char = text:sub(index, index)
    if char == "<" then
      depth = depth + 1
    elseif char == ">" then
      if depth > 0 then
        depth = depth - 1
      end
    elseif char == "," and depth == 0 then
      parts[#parts + 1] = text:sub(start, index - 1)
      start = index + 1
    end
  end
  parts[#parts + 1] = text:sub(start)
  return parts
end

---Extracts base type names from a class declaration line.
---@param class_line string|nil
---@return string[]
function M.parse_base_names(class_line)
  if type(class_line) ~= "string" then
    return {}
  end
  local colon = class_line:find(":", 1, true)
  if not colon then
    return {}
  end
  local bases = class_line:sub(colon + 1)
  local boundary = bases:find("[{};]")
  if boundary then
    bases = bases:sub(1, boundary - 1)
  end
  -- `where` constraints may contain `:` and `new()`; they end the base list.
  local where = bases:find("%f[%w_]where%s")
  if where then
    bases = bases:sub(1, where - 1)
  end
  local names = {}
  for _, part in ipairs(split_base_list(bases)) do
    local name = M.strip_generics(part)
    if name ~= "" and not name:find("(", 1, true) then
      names[#names + 1] = name
    end
  end
  return names
end

local function before_paren(value)
  if type(value) ~= "string" then
    return nil
  end
  local paren = value:find("(", 1, true)
  local head = trim(paren and value:sub(1, paren - 1) or value)
  if head == "" then
    return nil
  end
  return head
end

---Normalizes a method name by dropping its parameter list.
---@param name string|nil
---@param detail string|nil
---@return string
function M.normalize_method_name(name, detail)
  return before_paren(name) or before_paren(detail) or ""
end

---Extracts the class name from a `textDocument/hover` markdown answer.
---Only the first line of the ```csharp block is considered.
---@param markdown string|nil
---@return string|nil
function M.parse_hover_class(markdown)
  if type(markdown) ~= "string" then
    return nil
  end
  local fence = markdown:find("```csharp", 1, true)
  if not fence then
    return nil
  end
  local first_newline = markdown:find("\n", fence + 9, true)
  if not first_newline then
    return nil
  end
  local next_newline = markdown:find("\n", first_newline + 1, true)
  local first_line = markdown:sub(first_newline + 1, (next_newline or (#markdown + 1)) - 1)
  return trim(first_line):match("^class%s+([%w_%.]+)")
end

local function contents_to_text(contents)
  if type(contents) == "string" then
    return contents
  end
  if type(contents) ~= "table" then
    return nil
  end
  if type(contents.value) == "string" then
    return contents.value
  end
  local parts = {}
  for _, part in ipairs(contents) do
    if type(part) == "string" then
      parts[#parts + 1] = part
    elseif type(part) == "table" and type(part.value) == "string" then
      parts[#parts + 1] = part.value
    end
  end
  return #parts > 0 and table.concat(parts, "\n") or nil
end

local function node_range(node)
  if type(node) ~= "table" then
    return nil
  end
  local range = node.range
  if type(range) ~= "table" and type(node.location) == "table" then
    range = node.location.range
  end
  if
    type(range) ~= "table"
    or type(range.start) ~= "table"
    or type(range["end"]) ~= "table"
  then
    return nil
  end
  return range
end

local function position_ge(left, right)
  if left.line ~= right.line then
    return left.line > right.line
  end
  return left.character >= right.character
end

local function position_le(left, right)
  if left.line ~= right.line then
    return left.line < right.line
  end
  return left.character <= right.character
end

local function range_contains(range, position)
  return position_ge(position, range.start) and position_le(position, range["end"])
end

local function cursor_of(bufnr)
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current_win) == bufnr then
    local cursor = vim.api.nvim_win_get_cursor(current_win)
    return { line = cursor[1] - 1, character = cursor[2] }
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, win_buf = pcall(vim.api.nvim_win_get_buf, win)
    if ok and win_buf == bufnr then
      local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      if ok_cursor then
        return { line = cursor[1] - 1, character = cursor[2] }
      end
    end
  end
  return { line = 0, character = 0 }
end

-- Returns the innermost class symbol containing the position. The span is
-- measured in lines, which is enough to pick nested classes apart.
local function select_class(nodes, position, best)
  for _, node in ipairs(nodes or {}) do
    if type(node) == "table" then
      local range = node_range(node)
      local children = type(node.children) == "table" and node.children or nil
      if node.kind == CLASS_KIND and range and range_contains(range, position) then
        local span = range["end"].line - range.start.line
        if not best or span <= best.span then
          best = { node = node, span = span }
        end
        best = select_class(children, position, best)
      elseif children then
        best = select_class(children, position, best)
      end
    end
  end
  return best
end

local function method_info(class_sym)
  local implemented = {}
  local ranges = {}
  for _, child in ipairs(class_sym.children or {}) do
    if type(child) == "table" and child.kind == METHOD_KIND then
      local name = M.normalize_method_name(child.name, child.detail)
      if name ~= "" then
        implemented[name] = true
        local range = node_range(child)
        if range then
          ranges[#ranges + 1] = {
            start_line = range.start.line,
            end_line = range["end"].line,
          }
        end
      end
    end
  end
  return implemented, ranges
end

-- Source is `{ uri, lines, start_line, bufnr }`; lines is the declaration
-- file's full text and start_line points at the class declaration.
local function declaration_lines(source)
  local lines = {}
  for offset = 0, 3 do
    local line = source.lines[source.start_line + offset + 1]
    if line == nil then
      break
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- Class declarations may spread the base list over a few lines, so the
-- following lines are joined until a base name appears.
local function source_bases(source)
  local declared = declaration_lines(source)
  if #declared == 0 then
    return {}, declared
  end
  local bases = M.parse_base_names(declared[1])
  for index = 2, #declared do
    if #bases > 0 then
      break
    end
    bases = M.parse_base_names(table.concat(declared, " ", 1, index))
  end
  return bases, declared
end

local function find_identifier(declared, source, plain)
  for index, line in ipairs(declared) do
    local colon = line:find(":", 1, true)
    local init = colon and (colon + 1) or 1
    local position = line:find(plain, init, true)
    if position then
      return { line = source.start_line + index - 1, character = position - 1 }
    end
  end
  return nil
end

local function supports_workspace_symbols(client)
  local capabilities = client and client.server_capabilities
  if type(capabilities) ~= "table" then
    return false
  end
  local provider = capabilities.workspaceSymbolProvider
  return provider == true or type(provider) == "table"
end

local function is_expired(state)
  return state.uv.now() >= state.deadline
end

local function read_source_lines(uri)
  local ok_path, path = pcall(vim.uri_to_fname, uri)
  if not ok_path or type(path) ~= "string" then
    return nil
  end
  local ok_bufnr, bufnr = pcall(vim.fn.bufnr, path)
  if ok_bufnr and bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    local ok_loaded, loaded = pcall(vim.api.nvim_buf_is_loaded, bufnr)
    if ok_loaded and loaded then
      local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
      if ok_lines and type(lines) == "table" then
        return lines, bufnr
      end
    end
  end
  local ok_lines, lines = pcall(vim.fn.readfile, path)
  if not ok_lines or type(lines) ~= "table" then
    return nil
  end
  return lines, nil
end

local resolve_kind

-- Follows the hover answer of a project class through `workspace/symbol` and
-- reads its declaration to continue the chain.
local function follow_symbol(state, plain, depth, on_done)
  if state.finished then
    return
  end
  if is_expired(state) then
    return on_done(nil)
  end
  if not supports_workspace_symbols(state.client) then
    return on_done(nil)
  end
  state.client:request("workspace/symbol", { query = plain }, function(err, result)
    if state.finished then
      return
    end
    if is_expired(state) then
      return on_done(nil)
    end
    if err or type(result) ~= "table" then
      return on_done(nil)
    end
    local symbol
    for _, item in ipairs(result) do
      if type(item) == "table" and item.name == plain and item.kind == CLASS_KIND then
        symbol = item
        break
      end
    end
    local range = node_range(symbol)
    local uri = symbol and symbol.location and symbol.location.uri
    if not range or type(uri) ~= "string" then
      return on_done(nil)
    end
    local lines, bufnr = read_source_lines(uri)
    if not lines then
      return on_done(nil)
    end
    resolve_kind(state, {
      uri = uri,
      lines = lines,
      start_line = range.start.line,
      bufnr = bufnr,
    }, depth + 1, on_done)
  end)
end

-- Walks the base list of one declaration: short Unity names resolve locally,
-- everything else goes through hover and, for project classes, the chain.
resolve_kind = function(state, source, depth, on_done)
  if state.finished then
    return
  end
  if depth >= MAX_DEPTH or is_expired(state) then
    return on_done(nil)
  end
  local bases, declared = source_bases(source)
  local index = 0

  local next_base
  next_base = function()
    if state.finished then
      return
    end
    if is_expired(state) then
      return on_done(nil)
    end
    index = index + 1
    local base = bases[index]
    if not base then
      return on_done(nil)
    end
    local plain = M.strip_generics(base)
    if plain == "" then
      return next_base()
    end
    local kind = fallback.classify(plain)
    if kind then
      return on_done(kind)
    end
    local position = find_identifier(declared, source, plain)
    if not position then
      return next_base()
    end
    state.client:request("textDocument/hover", {
      textDocument = { uri = source.uri },
      position = position,
    }, function(err, result)
      if state.finished then
        return
      end
      if is_expired(state) then
        return on_done(nil)
      end
      if err or type(result) ~= "table" then
        return next_base()
      end
      local qualified = M.parse_hover_class(contents_to_text(result.contents))
      if not qualified then
        return next_base()
      end
      local hovered_kind = fallback.classify(qualified)
      if hovered_kind then
        return on_done(hovered_kind)
      end
      follow_symbol(state, plain, depth, on_done)
    end, source.bufnr)
  end

  next_base()
end

---Resolves the context through the buffer's LSP client.
---`done` is called exactly once: with a context, or with nil when no client
---can answer, the chain is unresolved, or `cfg.timeout_ms` elapses.
---@param bufnr integer|nil
---@param cfg table
---@param done fun(ctx: unitykit.Context|nil)
function M.resolve(bufnr, cfg, done)
  if type(done) ~= "function" then
    return
  end
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    done(nil)
    return
  end

  local ok_clients, clients = pcall(vim.lsp.get_clients, {
    bufnr = bufnr,
    method = "textDocument/documentSymbol",
  })
  local client = ok_clients and clients and clients[1] or nil
  if not client or type(client.request) ~= "function" then
    done(nil)
    return
  end

  local uv = vim.uv or vim.loop
  local timeout = tonumber(cfg and cfg.timeout_ms) or DEFAULT_TIMEOUT
  if timeout < 0 then
    timeout = 0
  end

  local state = {
    uv = uv,
    client = client,
    deadline = uv.now() + timeout,
    finished = false,
    timer = nil,
  }

  local function finish(ctx)
    if state.finished then
      return
    end
    state.finished = true
    if state.timer then
      local timer = state.timer
      state.timer = nil
      pcall(function()
        timer:stop()
      end)
      pcall(function()
        timer:close()
      end)
    end
    done(ctx)
  end

  local ok_timer, timer = pcall(uv.new_timer)
  if ok_timer and timer then
    state.timer = timer
    local ok_start = pcall(function()
      timer:start(timeout, 0, function()
        finish(nil)
      end)
    end)
    if not ok_start then
      state.timer = nil
      pcall(function()
        timer:close()
      end)
    end
  end

  local uri = vim.uri_from_bufnr(bufnr)
  local ok_request = pcall(client.request, client, "textDocument/documentSymbol", {
    textDocument = { uri = uri },
  }, function(err, result)
    if state.finished then
      return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return finish(nil)
    end
    if err or type(result) ~= "table" then
      return finish(nil)
    end
    local selected = select_class(result, cursor_of(bufnr))
    local class_sym = selected and selected.node
    local range = node_range(class_sym)
    if not class_sym or not range then
      return finish(nil)
    end
    local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
    if not ok_lines or type(lines) ~= "table" then
      return finish(nil)
    end
    local implemented, method_ranges = method_info(class_sym)
    local class_range = {
      start_line = range.start.line,
      end_line = range["end"].line,
    }
    resolve_kind(state, {
      uri = uri,
      lines = lines,
      start_line = range.start.line,
      bufnr = bufnr,
    }, 0, function(kind)
      if state.finished then
        return
      end
      if not kind then
        return finish(nil)
      end
      finish({
        class_name = class_sym.name,
        class_kind = kind,
        class_range = class_range,
        method_ranges = method_ranges,
        implemented = implemented,
        source = "lsp",
      })
    end)
  end, bufnr)
  if not ok_request then
    finish(nil)
  end
end

return M
