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

-- Scans the buffer once: line starts and byte ranges occupied by comments or
-- string/char literals. Later lookups are binary searches over these tables,
-- so resolving does not rescan the whole text per identifier.
local function build_scan(text)
  local scan = { text = text, line_starts = { 1 }, ignored = {} }
  local i = 1
  local length = #text
  while i <= length do
    local char = text:sub(i, i)
    local next_char = text:sub(i + 1, i + 1)
    if char == "\n" then
      scan.line_starts[#scan.line_starts + 1] = i + 1
      i = i + 1
    elseif char == '"' or char == "'" then
      local after = skip_literal(text, i)
      scan.ignored[#scan.ignored + 1] = { start = i, finish = after - 1 }
      i = after
    elseif char == "/" and next_char == "/" then
      local newline = text:find("\n", i + 2, true)
      local finish = newline and (newline - 1) or length
      scan.ignored[#scan.ignored + 1] = { start = i, finish = finish }
      i = newline or (length + 1)
    elseif char == "/" and next_char == "*" then
      local close = text:find("*/", i + 2, true)
      local finish = close and (close + 1) or length
      scan.ignored[#scan.ignored + 1] = { start = i, finish = finish }
      i = close and (close + 2) or (length + 1)
    else
      i = i + 1
    end
  end
  return scan
end

local function line_index(scan, pos)
  local starts = scan.line_starts
  local low, high = 1, #starts
  local found = 1
  while low <= high do
    local mid = math.floor((low + high) / 2)
    if starts[mid] <= pos then
      found = mid
      low = mid + 1
    else
      high = mid - 1
    end
  end
  return found
end

-- 0-based line number for a 1-based byte position.
local function line_of(scan, pos)
  return line_index(scan, pos) - 1
end

local function line_start_of(scan, pos)
  return scan.line_starts[line_index(scan, pos)]
end

local function inside_ignored(scan, pos)
  local ranges = scan.ignored
  local low, high = 1, #ranges
  local found = 0
  while low <= high do
    local mid = math.floor((low + high) / 2)
    if ranges[mid].start <= pos then
      found = mid
      low = mid + 1
    else
      high = mid - 1
    end
  end
  return found > 0 and pos <= ranges[found].finish
end

-- Commented matches are skipped. The line-prefix guard mirrors the plan;
-- ignored ranges already cover string literals and block comments.
local function is_ignored(scan, pos)
  if inside_ignored(scan, pos) then
    return true
  end
  local text = scan.text
  local i = line_start_of(scan, pos)
  while i < pos do
    local char = text:sub(i, i)
    if not char:match("%s") then
      break
    end
    i = i + 1
  end
  if i >= pos then
    return false
  end
  if text:sub(i, i + 1) == "//" then
    return true
  end
  return text:sub(i, i) == "*"
end

local function find_unquoted(scan, init, needle)
  local pos = init
  while true do
    local found = scan.text:find(needle, pos, true)
    if not found then
      return nil
    end
    if not inside_ignored(scan, found) then
      return found
    end
    pos = found + 1
  end
end

local function first_range_ending_after(ranges, pos)
  local low, high = 1, #ranges
  local found = #ranges + 1
  while low <= high do
    local mid = math.floor((low + high) / 2)
    if ranges[mid].finish >= pos then
      found = mid
      high = mid - 1
    else
      low = mid + 1
    end
  end
  return found
end

-- Finds the matching closing delimiter. A pointer walks the sorted ignored
-- ranges, so comments and literals are skipped without rescanning them.
local function match_pair(scan, open_pos, open_char, close_char)
  local text = scan.text
  local ranges = scan.ignored
  local index = first_range_ending_after(ranges, open_pos)
  local depth = 0
  local i = open_pos
  local length = #text
  while i <= length do
    local range = ranges[index]
    if range and i > range.finish then
      index = index + 1
    elseif range and i >= range.start then
      i = range.finish + 1
      index = index + 1
    else
      local char = text:sub(i, i)
      if char == open_char then
        depth = depth + 1
      elseif char == close_char then
        depth = depth - 1
        if depth == 0 then
          return i
        end
      end
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

-- `where` constraints may contain `:` and `class`; they are not part of the
-- base list. Truncate the declaration segment at the first `where` clause.
local function before_where(segment)
  local init = 1
  while true do
    local found = segment:find("%f[%w_]where", init)
    if not found then
      return segment
    end
    local after = segment:sub(found + 5, found + 5)
    if after == "" or not after:match("[%w_]") then
      return segment:sub(1, found - 1)
    end
    init = found + 5
  end
end

local CLASS_BOUNDARIES = {
  ["]"] = true,
  [";"] = true,
  ["}"] = true,
  ["{"] = true,
}

local CLASS_PREFIX_WORDS = {
  ["record"] = true,
  ["file"] = true,
}

-- A declaration's `class` keyword follows the line start or a modifier.
-- This rejects `where T : class` (preceded by `:`) and avoids matching the
-- constraint keyword as a class declaration.
local function is_class_declaration(scan, pos)
  local text = scan.text
  local line_start = line_start_of(scan, pos)
  local i = pos - 1
  while i >= line_start do
    local char = text:sub(i, i)
    if not char:match("%s") then
      break
    end
    i = i - 1
  end
  if i < line_start then
    return true
  end
  local char = text:sub(i, i)
  if CLASS_BOUNDARIES[char] then
    return true
  end
  if not char:match("[%w_]") then
    return false
  end
  local word_start = i
  while word_start > line_start do
    local previous = text:sub(word_start - 1, word_start - 1)
    if not previous:match("[%w_]") then
      break
    end
    word_start = word_start - 1
  end
  local word = text:sub(word_start, i)
  return MODIFIERS[word] == true or CLASS_PREFIX_WORDS[word] == true
end

local function find_classes(scan)
  local classes = {}
  local text = scan.text
  local init = 1
  local length = #text
  while init <= length do
    local match_start, match_end, name = text:find("%f[%w_]class%s+([%w_]+)", init)
    if not match_start then
      break
    end
    init = match_end + 1
    local declaration = not is_ignored(scan, match_start)
      and is_class_declaration(scan, match_start)
    if name and declaration then
      local body_start = find_unquoted(scan, match_end + 1, "{")
      if body_start then
        local body_end = match_pair(scan, body_start, "{", "}") or length
        local segment = text:sub(match_end + 1, body_start - 1)
        local base = base_name(before_where(segment))
        classes[#classes + 1] = {
          name = name,
          kind = M.classify(base),
          start_line = line_of(scan, match_start),
          end_line = line_of(scan, body_end),
          span_start = line_start_of(scan, match_start),
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
local function is_declaration_prefix(scan, name_start)
  local text = scan.text
  local prefix = text:sub(line_start_of(scan, name_start), name_start - 1)
  prefix = trim(prefix:gsub("%b[]", " "))
  local tail = trim(prefix:match("([^;{}]*)$") or prefix)
  if tail == "" then
    return false
  end
  if tail:sub(-1) == "." or tail:sub(-1) == "~" then
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
  -- Tuple return types contain parentheses; replace balanced groups with a
  -- type placeholder before looking for calls and assignments.
  local normalized = tail:gsub("%b()", " __tuple ")
  if normalized:find("=") or normalized:find("%(") then
    return false
  end
  local rest = strip_modifiers(normalized)
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

-- Skips `where ...` clauses between the parameter list and the body.
local function body_after_params(scan, params_end)
  local text = scan.text
  local length = #text
  local i = params_end + 1
  while i <= length do
    local char = text:sub(i, i)
    if char:match("%s") then
      i = i + 1
    elseif text:sub(i, i + 4) == "where" and not text:sub(i + 5, i + 5):match("[%w_]") then
      i = i + 5
      while i <= length do
        local current = text:sub(i, i)
        if current == "{" or current == ";" then
          break
        end
        if current == "=" and text:sub(i + 1, i + 1) == ">" then
          break
        end
        i = i + 1
      end
    else
      break
    end
  end
  return i
end

local function collect_methods(scan, selected, classes)
  local text = scan.text
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
    local ignored = inside_ignored(scan, name_start)
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
        local params_end = match_pair(scan, after_name, "(", ")")
        if params_end then
          handled = true
          pos = params_end + 1
          if not METHOD_SKIP_NAMES[name] and is_declaration_prefix(scan, name_start) then
            local start_line = line_of(scan, name_start)
            local end_line = start_line
            local body = body_after_params(scan, params_end)
            if text:sub(body, body) == "{" then
              local close = match_pair(scan, body, "{", "}")
              if close then
                end_line = line_of(scan, close)
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

local function select_class(classes, offset)
  local best
  for _, class in ipairs(classes) do
    if offset >= class.span_start and offset <= class.body_end then
      if not best or (class.body_end - class.span_start) < (best.body_end - best.span_start) then
        best = class
      end
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
  local scan = build_scan(text)
  local row, col = cursor_of(bufnr)
  local offset = cursor_offset(lines, text, row, col)
  local classes = find_classes(scan)
  local selected = select_class(classes, offset)
  if not selected then
    return empty_context()
  end
  local method_ranges, implemented = collect_methods(scan, selected, classes)
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
