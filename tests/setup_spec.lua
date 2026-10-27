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

h.finish()
