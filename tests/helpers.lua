-- Plain helpers for headless specs (loaded via dofile, no runtimepath needed).
local M = {}

local passed = 0
local failed = 0

function M.check(cond, label)
  if cond then
    passed = passed + 1
    print("ok   - " .. label)
  else
    failed = failed + 1
    print("FAIL - " .. label)
  end
end

function M.eq(actual, expected, label)
  local same = vim.deep_equal(actual, expected)
  if not same then
    print("  actual:   " .. vim.inspect(actual))
    print("  expected: " .. vim.inspect(expected))
  end
  M.check(same, label)
end

function M.finish()
  print(string.format("%d passed, %d failed", passed, failed))
  os.exit(failed == 0 and 0 or 1)
end

function M.new_buf(lines, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = filetype or "cs"
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return bufnr
end

function M.make_unity_project()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/Assets", "p")
  vim.fn.mkdir(dir .. "/ProjectSettings", "p")
  local f = io.open(dir .. "/ProjectSettings/ProjectVersion.txt", "w")
  f:write("m_EditorVersion: 6000.0.0f1\n")
  f:close()
  return dir
end

return M
