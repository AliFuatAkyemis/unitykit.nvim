local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local project = require("unitykit.project")

local dir = h.make_unity_project()
local fake = vim.fn.tempname()
vim.fn.mkdir(fake .. "/Assets", "p")
local buf = h.new_buf({ "public class A {}" }, "cs")
vim.api.nvim_buf_set_name(buf, dir .. "/Assets/Scripts/A.cs")

h.eq(project.root(buf), dir, "Assets + ProjectVersion -> kok")

-- nested 3 levels
local deep = dir .. "/Assets/Scripts/Sub/Deep/B.cs"
vim.fn.mkdir(vim.fn.fnamemodify(deep, ":h"), "p")
vim.api.nvim_buf_set_name(buf, deep)
h.eq(project.root(buf), dir, "ust dizinlere yurur")

-- only Assets, no ProjectVersion
vim.api.nvim_buf_set_name(buf, fake .. "/Assets/C.cs")
h.eq(project.root(buf), nil, "ProjectVersion yoksa kok yok")

-- unnamed buffer
local anon = h.new_buf({ "public class N {}" }, "cs")
h.eq(project.root(anon), nil, "isimsiz buffer nil")

-- cache invalidation
vim.api.nvim_buf_set_name(buf, dir .. "/Assets/Scripts/A.cs")
project.root(buf)
vim.api.nvim_buf_set_name(buf, fake .. "/Assets/C.cs")
h.eq(project.root(buf), nil, "isim degisince cache gecersiz")

-- reset(nil) temizler, sonraki cagri yine dogru kok dondurur
project.reset(nil)
vim.api.nvim_buf_set_name(buf, dir .. "/Assets/Scripts/A.cs")
h.eq(project.root(buf), dir, "reset sonrasi kok yeniden bulunur")

h.check(project.is_unity_root(dir), "is_unity_root dogru")
h.check(not project.is_unity_root(fake), "is_unity_root eksik kokte false")

-- cleanup: created temp dirs must not leak
vim.fn.delete(dir, "rf")
vim.fn.delete(fake, "rf")

h.finish()
