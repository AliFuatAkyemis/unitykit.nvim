local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local cfg = require("unitykit.config")

local defaults_snapshot = vim.deepcopy(cfg.defaults)

h.eq(cfg.setup(), {
  filetypes = { "cs" },
  body = "block",
  access = "none",
  hide_implemented = true,
  priority = true,
  timeout_ms = 1500,
}, "setup() varsayilanlari dondurur")

h.eq(cfg.setup({ body = "line", access = "public" }).access, "public", "override uygulanir")
h.eq(cfg.setup({ body = "line" }).body, "line", "body line")

local orig_notify = vim.notify
local notified = {}
local function stub_notify(msg, level)
  notified[#notified + 1] = { msg = msg, level = level }
end

-- Runs fn with the notify stub installed, restoring the original afterwards.
-- Returns the captured notifications and fn's return value.
local function run_notified(fn)
  notified = {}
  vim.notify = stub_notify
  local ok, res = pcall(fn)
  vim.notify = orig_notify
  if not ok then
    error(res)
  end
  return notified, res
end

local function check_notify(items, key, label)
  h.check(#items == 1, label .. " icin tek uyari")
  local has_key = #items > 0 and items[1].msg:find(key, 1, true) ~= nil
  h.check(has_key, label .. " uyari mesaji anahtari icerir")
  if #items > 0 then
    h.eq(items[1].level, vim.log.levels.WARN, label .. " uyari seviyesi WARN")
  end
end

local warns, config = run_notified(function()
  return cfg.setup({ body = "nope" })
end)
check_notify(warns, "body", "gecersiz body")
h.eq(config.body, "block", "gecersiz body -> block")

warns, config = run_notified(function()
  return cfg.setup({ access = "nope" })
end)
check_notify(warns, "access", "gecersiz access")
h.eq(config.access, "none", "gecersiz access -> none")

warns, config = run_notified(function()
  return cfg.setup({ filetypes = "cs" })
end)
check_notify(warns, "filetypes", "gecersiz filetypes")
h.eq(config.filetypes, { "cs" }, "gecersiz filetypes -> varsayilan")

warns, config = run_notified(function()
  return cfg.setup({ timeout_ms = "later" })
end)
h.check(#warns == 0, "gecersiz timeout_ms uyari gerektirmez")
h.eq(config.timeout_ms, 1500, "gecersiz timeout_ms -> 1500")

local user = { body = "line" }
cfg.setup(user)
h.eq(user, { body = "line" }, "kullanici tablosu degistirilmez")

h.eq(
  cfg.setup({ filetypes = { "cs", "razor" } }).filetypes,
  { "cs", "razor" },
  "filetypes kopyalanir"
)

h.eq(cfg.get(), {
  filetypes = { "cs", "razor" },
  body = "block",
  access = "none",
  hide_implemented = true,
  priority = true,
  timeout_ms = 1500,
}, "get() son setup sonucunu dondurur")

h.eq(cfg.defaults, defaults_snapshot, "defaults degismez")

package.loaded["unitykit.config"] = nil
cfg = require("unitykit.config")
h.eq(cfg.get(), defaults_snapshot, "get() setup oncesi varsayilanlari dondurur")

h.finish()
