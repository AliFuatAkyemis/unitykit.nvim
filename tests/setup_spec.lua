local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local registered = 0
local fake_cmp = {
  register_source = function(name)
    registered = registered + 1
    assert(name == "unitykit")
  end,
}
package.loaded["cmp"] = fake_cmp

local unitykit = require("unitykit")
local cfg = unitykit.setup({ body = "line" })
h.eq(cfg.body, "line", "setup opts uygular")
unitykit.setup({})
h.eq(registered, 1, "source iki kez kaydedilmez")
h.eq(require("unitykit.config").get().body, "block", "son setup gecerli")

package.loaded.cmp = nil
package.loaded["unitykit.completion.cmp"] = nil
package.loaded["unitykit"] = nil
local ok = pcall(function() require("unitykit").setup({}) end)
h.check(ok, "cmp yokken setup hata vermez")

h.check(type(require("unitykit.health").check) == "function", "health.check var")

-- A failed registration must not burn the one-shot guard: once cmp appears,
-- the next setup() registers the source.
local retried = 0
package.loaded["cmp"] = {
  register_source = function(name)
    retried = retried + 1
    assert(name == "unitykit")
  end,
}
require("unitykit").setup({})
h.eq(retried, 1, "cmp sonradan gelince setup kaydeder")
require("unitykit").setup({})
h.eq(retried, 1, "basari sonrasi tekrar kaydedilmez")

-- Health is read-only: it reads the cached context and never asks the LSP.
local dir = h.make_unity_project()
local probe = h.new_buf({
  "public class Probe : MonoBehaviour",
  "{",
  "}",
}, "cs")
vim.api.nvim_buf_set_name(probe, dir .. "/Assets/Probe.cs")
local cache = require("unitykit.context.cache")
cache.set(probe, {
  source = "fallback",
  class_name = "Probe",
  class_kind = "monobehaviour",
})
local resolve_calls = 0
local saved_lsp = package.loaded["unitykit.context.lsp"]
package.loaded["unitykit.context.lsp"] = {
  resolve = function()
    resolve_calls = resolve_calls + 1
    error("health must not resolve context")
  end,
}
local checked = pcall(require("unitykit.health").check)
package.loaded["unitykit.context.lsp"] = saved_lsp
h.check(checked, "health.check hata vermez")
h.eq(resolve_calls, 0, "health cache okur, lsp istemez")

h.finish()
