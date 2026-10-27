local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local cfg = require("unitykit.config")

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

h.eq(cfg.setup({ body = "nope" }).body, "block", "gecersiz body -> block")
h.eq(cfg.setup({ access = "nope" }).access, "none", "gecersiz access -> none")

local notified = {}
local orig = vim.notify
vim.notify = function(msg)
  notified[#notified + 1] = msg
end
cfg.setup({ body = "nope" })
vim.notify = orig
h.check(#notified == 1, "gecersiz ayar icin tek uyari")

local user = { body = "line" }
cfg.setup(user)
h.eq(user, { body = "line" }, "kullanici tablosu degistirilmez")

h.eq(cfg.setup({ filetypes = { "cs", "razor" } }).filetypes, { "cs", "razor" }, "filetypes kopyalanir")

h.finish()
