-- Regex-based fallback context resolution for C# buffers.
-- Used when no LSP is available or its answer times out. Line numbers are
-- 0-based and `end_line` is inclusive.
local M = {}

local MODIFIERS = {
  ["public"] = true,
  ["private"] = true,
  ["protected"] = true,
  ["internal"] = true,
  ["static"] = true,
  ["virtual"] = true,
  ["override"] = true,
  ["abstract"] = true,
  ["sealed"] = true,
  ["extern"] = true,
  ["unsafe"] = true,
  ["async"] = true,
  ["partial"] = true,
  ["new"] = true,
  ["readonly"] = true,
  ["volatile"] = true,
}

local METHOD_SKIP_NAMES = {
  ["class"] = true,
  ["struct"] = true,
  ["interface"] = true,
  ["new"] = true,
  ["return"] = true,
  ["if"] = true,
  ["for"] = true,
  ["foreach"] = true,
  ["while"] = true,
  ["switch"] = true,
  ["using"] = true,
  ["namespace"] = true,
  ["get"] = true,
  ["set"] = true,
}

local PREFIX_KEYWORDS = {
  ["return"] = true,
  ["new"] = true,
  ["throw"] = true,
  ["await"] = true,
  ["else"] = true,
  ["case"] = true,
  ["goto"] = true,
  ["yield"] = true,
  ["using"] = true,
  ["lock"] = true,
  ["catch"] = true,
  ["typeof"] = true,
  ["sizeof"] = true,
  ["nameof"] = true,
  ["base"] = true,
  ["this"] = true,
  ["if"] = true,
  ["for"] = true,
  ["foreach"] = true,
  ["while"] = true,
  ["switch"] = true,
  ["do"] = true,
  ["try"] = true,
  ["finally"] = true,
}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function empty_context()
  return {
    class_name = nil,
    class_kind = nil,
    class_range = nil,
    method_ranges = {},
    implemented = {},
    source = "fallback",
  }
end

-- Counts newlines before `pos`; the result is a 0-based line number.
local function line_of(text, pos)
  local _, count = text:sub(1, math.max(pos - 1, 0)):gsub("\n", "")
  return count
end

local function line_start_of(text, pos)
  local newline = text:sub(1, pos - 1):match(".*()\n")
  return newline and (newline + 1) or 1
end

-- Returns the byte position just after a string/char literal (or the newline
-- position when a regular literal is not terminated on that line).
local function skip_literal(text, pos)
  local quote = text:sub(pos, pos)
  local i = pos + 1
  local length = #text
  while i <= length do
    local char = text:sub(i, i)
    if char == "\\" then
      i = i + 2
    elseif char == quote then
      return i + 1
    elseif char == "\n" then
      return i
    else
      i = i + 1
    end
  end
  return length + 1
end

-- Pragmatic scanner: decides whether `target` is inside a comment or literal.
-- It is intentionally small; C# has more lexical corners than this fallback.
local function is_commented_or_string(text, target)
  local i = 1
  local length = #text
  while i < target do
    local char = text:sub(i, i)
    local next_char = text:sub(i + 1, i + 1)
    if char == '"' or char == "'" then
      local after = skip_literal(text, i)
      if after > target then
        return true
      end
      i = after
    elseif char == "/" and next_char == "/" then
      local newline = text:find("\n", i + 2, true)
      if not newline or newline >= target then
        return true
      end
      i = newline + 1
    elseif char == "/" and next_char == "*" then
      local close = text:find("*/", i + 2, true)
      if not close or close + 2 > target then
        return true
      end
      i = close + 2
    else
      i = i + 1
    end
  end
  return false
end

-- Commented matches are skipped. The line-prefix check is the cheap guard
-- described by the plan; the scanner handles string literals as well.
local function is_ignored(text, pos)
  if is_commented_or_string(text, pos) then
    return true
  end
  local prefix = text:sub(line_start_of(text, pos), pos - 1):gsub("^%s+", "")
  return prefix:match("^//") ~= nil or prefix:match("^%*") ~= nil
end

local function find_unquoted(text, init, needle)
  local pos = init
  while true do
    local found = text:find(needle, pos, true)
    if not found then
      return nil
    end
    if not is_commented_or_string(text, found) then
      return found
    end
    pos = found + 1
  end
end

-- Finds the matching closing delimiter, skipping comments and literals.
local function match_pair(text, open_pos, open_char, close_char)
  local depth = 0
  local i = open_pos
  local length = #text
  while i <= length do
    local char = text:sub(i, i)
    local next_char = text:sub(i + 1, i + 1)
    if char == '"' or char == "'" then
      i = skip_literal(text, i)
    elseif char == "/" and next_char == "/" then
      local newline = text:find("\n", i + 2, true)
      i = newline and (newline + 1) or (length + 1)
    elseif char == "/" and next_char == "*" then
      local close = text:find("*/", i + 2, true)
      i = close and (close + 2) or (length + 1)
    elseif char == open_char then
      depth = depth + 1
      i = i + 1
    elseif char == close_char then
      depth = depth - 1
      if depth == 0 then
        return i
      end
      i = i + 1
    else
      i = i + 1
    end
  end
  return nil
end

---Maps a Unity base type name to a message kind.
---@param name string|nil
---@return "monobehaviour"|"scriptableobject"|"editor"|nil
function M.classify(name)
  if type(name) ~= "string" then
    return nil
  end
  local cleaned = trim(name:gsub("<[^>]*>", ""))
  local short = cleaned:match("([%w_]+)%s*$")
  if short == "MonoBehaviour" then
    return "monobehaviour"
  elseif short == "ScriptableObject" then
    return "scriptableobject"
  elseif short == "Editor" then
    return "editor"
  end
  return nil
end

local function base_name(segment)
  local colon = segment:find(":", 1, true)
  if not colon then
    return nil
  end
  local base = segment:sub(colon + 1)
  base = base:gsub("//[^\n]*", "")
  base = base:gsub("/%*.-%*/", "")
  local comma = base:find(",", 1, true)
  if comma then
    base = base:sub(1, comma - 1)
  end
  base = trim(base:gsub("<[^>]*>", ""))
  if base == "" then
    return nil
  end
  return base
end

local function find_classes(text)
  local classes = {}
  local init = 1
  local length = #text
  while init <= length do
    local match_start, match_end, name = text:find("%f[%w_]class%s+([%w_]+)", init)
    if not match_start then
      break
    end
    init = match_end + 1
    if name and not is_ignored(text, match_start) then
      local body_start = find_unquoted(text, match_end + 1, "{")
      if body_start then
        local body_end = match_pair(text, body_start, "{", "}") or length
        local segment = text:sub(match_end + 1, body_start - 1)
        local base = base_name(segment)
        classes[#classes + 1] = {
          name = name,
          kind = M.classify(base),
          start_line = line_of(text, match_start),
          end_line = line_of(text, body_end),
          span_start = line_start_of(text, match_start),
          body_start = body_start,
          body_end = body_end,
        }
      end
    end
  end
  return classes
end

local function strip_modifiers(prefix)
  local rest = trim(prefix)
  while true do
    local modifier, after = rest:match("^([%a_][%w_]*)%s+(.*)$")
    if not modifier or not MODIFIERS[modifier] then
      break
    end
    rest = trim(after)
  end
  if MODIFIERS[rest] then
    return ""
  end
  return rest
end

-- A declaration has a type before the name. Calls, assignments, control flow
-- and attribute names are rejected, since their prefix does not look like one.
local function is_declaration_prefix(text, name_start)
  local prefix = text:sub(line_start_of(text, name_start), name_start - 1)
  prefix = trim(prefix:gsub("%b[]", " "))
  local tail = trim(prefix:match("([^;{}]*)$") or prefix)
  if tail == "" then
    return false
  end
  if tail:sub(-1) == "." then
    return false
  end
  if tail:find("[=(]") then
    return false
  end
  if tail:find("[%[%]]") or tail:find("[\"']") then
    return false
  end
  if tail:find("%sdelegate%s") or tail:match("^delegate%s") or tail:match("%sdelegate$") then
    return false
  end
  if
    tail:find("%soperator%s")
    or tail:match("^operator%s")
    or tail:match("%soperator$")
  then
    return false
  end
  local rest = strip_modifiers(tail)
  if rest == "" then
    return false
  end
  local first = rest:match("^([%a_][%w_]*)")
  return not (first and PREFIX_KEYWORDS[first])
end

local function in_nested_body(pos, selected, classes)
  for _, class in ipairs(classes) do
    if
      class ~= selected
      and class.body_start > selected.body_start
      and class.body_end <= selected.body_end
      and pos >= class.body_start
      and pos <= class.body_end
    then
      return true
    end
  end
  return false
end

local function collect_methods(text, selected, classes)
  local ranges = {}
  local implemented = {}
  local pos = selected.body_start + 1
  local limit = selected.body_end - 1
  while pos <= limit do
    local name_start, name_end, name = text:find("([%a_][%w_]*)", pos)
    if not name_start or name_start > limit then
      break
    end
    local handled = false
    local ignored = is_commented_or_string(text, name_start)
      or in_nested_body(name_start, selected, classes)
    if not ignored then
      local after_name = name_end + 1
      while after_name <= limit and text:sub(after_name, after_name):match("%s") do
        after_name = after_name + 1
      end
      if text:sub(after_name, after_name) == "<" then
        local close = text:find(">", after_name + 1, true)
        if close and close <= limit then
          after_name = close + 1
          while after_name <= limit and text:sub(after_name, after_name):match("%s") do
            after_name = after_name + 1
          end
        end
      end
      if text:sub(after_name, after_name) == "(" then
        local params_end = match_pair(text, after_name, "(", ")")
        if params_end then
          handled = true
          pos = params_end + 1
          if not METHOD_SKIP_NAMES[name] and is_declaration_prefix(text, name_start) then
            local start_line = line_of(text, name_start)
            local end_line = start_line
            local body = params_end + 1
            while body <= #text and text:sub(body, body):match("%s") do
              body = body + 1
            end
            if text:sub(body, body) == "{" then
              local close = match_pair(text, body, "{", "}")
              if close then
                end_line = line_of(text, close)
              end
            end
            ranges[#ranges + 1] = { start_line = start_line, end_line = end_line }
            implemented[name] = true
          end
        end
      end
    end
    if not handled then
      pos = name_end + 1
    end
  end
  return ranges, implemented
end

local function cursor_of(bufnr)
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)
  if current_buf == bufnr then
    local cursor = vim.api.nvim_win_get_cursor(current_win)
    return cursor[1] - 1, cursor[2]
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, win_buf = pcall(vim.api.nvim_win_get_buf, win)
    if ok and win_buf == bufnr then
      local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      if ok_cursor then
        return cursor[1] - 1, cursor[2]
      end
    end
  end
  return 0, 0
end

-- Returns a 1-based byte position for the cursor, matching `string.find`.
local function cursor_offset(lines, text, row, col)
  if #lines == 0 then
    return 0
  end
  if row < 0 then
    row = 0
  end
  if row >= #lines then
    return #text + 1
  end
  if col < 0 then
    col = 0
  end
  local line = lines[row + 1]
  if col > #line then
    col = #line
  end
  local offset = col + 1
  for i = 1, row do
    offset = offset + #lines[i] + 1
  end
  return offset
end

local function select_class(classes, offset, row, text)
  local best
  for _, class in ipairs(classes) do
    if offset >= class.span_start and offset <= class.body_end then
      if not best or (class.body_end - class.span_start) < (best.body_end - best.span_start) then
        best = class
      end
    end
  end
  if not best and #classes == 1 then
    local only = classes[1]
    -- A cursor in the file preamble still gets the only class, provided the
    -- class uses a block body (an inline `class A { }` is not picked up).
    local body_line = line_of(text, only.body_start)
    if row < only.start_line and body_line > only.start_line then
      best = only
    end
  end
  return best
end

local function resolve_impl(bufnr)
  if bufnr == nil then
    bufnr = 0
  end
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if type(bufnr) ~= "number" or bufnr < 0 then
    return empty_context()
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok or type(lines) ~= "table" then
    return empty_context()
  end
  local text = table.concat(lines, "\n")
  local row, col = cursor_of(bufnr)
  local offset = cursor_offset(lines, text, row, col)
  local classes = find_classes(text)
  local selected = select_class(classes, offset, row, text)
  if not selected then
    return empty_context()
  end
  local method_ranges, implemented = collect_methods(text, selected, classes)
  return {
    class_name = selected.name,
    class_kind = selected.kind,
    class_range = { start_line = selected.start_line, end_line = selected.end_line },
    method_ranges = method_ranges,
    implemented = implemented,
    source = "fallback",
  }
end

---Resolves the innermost class around the cursor using regular expressions.
---Never errors: invalid buffers and unexpected content return an empty context.
---@param bufnr integer|nil
---@return unitykit.Context
function M.resolve(bufnr)
  local ok, context = pcall(resolve_impl, bufnr)
  if ok and type(context) == "table" then
    return context
  end
  return empty_context()
end

return M
