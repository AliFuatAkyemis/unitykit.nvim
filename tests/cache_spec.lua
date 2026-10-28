local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local cache = require("unitykit.context.cache")

local buf = h.new_buf({ "public class A : MonoBehaviour", "{", "}" }, "cs")
local ctx = {
  class_name = "A",
  class_kind = "monobehaviour",
  class_range = { start_line = 0, end_line = 2 },
  method_ranges = {},
  implemented = {},
  source = "fallback",
}

h.eq(cache.get(buf), nil, "bos cache nil")
h.check(cache.set(buf, ctx), "set true")
h.eq(cache.get(buf).class_name, "A", "cache hit")

vim.api.nvim_buf_set_lines(
  buf,
  0,
  -1,
  false,
  { "public class A : MonoBehaviour", "{", "  void Start() {}", "}" }
)
h.eq(cache.get(buf), nil, "changedtick degisince stale")
h.eq(cache.set(buf, ctx), true, "yeniden set")

h.eq(cache.pending(buf), false, "pending yok")
cache.invalidate(buf)
h.eq(cache.get(buf), nil, "invalidate temizler")

-- orchestration: fallback immediately, lsp later
local lsp_calls = 0
package.loaded["unitykit.context.lsp"] = {
  resolve = function(_, _, done)
    lsp_calls = lsp_calls + 1
    done({
      class_name = "A",
      class_kind = "scriptableobject",
      class_range = { start_line = 0, end_line = 3 },
      method_ranges = {},
      implemented = {},
      source = "lsp",
    })
  end,
}
package.loaded["unitykit.context"] = nil
local context = require("unitykit.context")

h.eq(
  context.resolve(buf, require("unitykit.config").setup()).source,
  "fallback",
  "ilk cagri aninda fallback"
)
h.eq(lsp_calls, 1, "lsp bir kez tetiklenir")
h.eq(
  context.resolve(buf, require("unitykit.config").setup()).source,
  "lsp",
  "lsp sonucu cache'e yazilir"
)
h.eq(lsp_calls, 1, "pending iken tekrar istek yok")

-- is_in_class_body
local c = {
  class_range = { start_line = 2, end_line = 10 },
  method_ranges = { { start_line = 5, end_line = 7 } },
}
h.check(context.is_in_class_body(c, 2), "sinif satiri govde sayilir")
h.check(context.is_in_class_body(c, 4), "metot disi govde")
h.check(not context.is_in_class_body(c, 5), "metot baslangici disarida")
h.check(not context.is_in_class_body(c, 6), "metot icinde degil")
h.check(not context.is_in_class_body(c, 11), "sinif disi")
h.check(not context.is_in_class_body({ class_range = nil }, 1), "sinif yoksa false")

-- change tick invalidates lsp result too
vim.api.nvim_buf_set_lines(
  buf,
  0,
  -1,
  false,
  { "public class A : MonoBehaviour", "{", "}", "// x" }
)
h.eq(
  context.resolve(buf, require("unitykit.config").setup()).source,
  "fallback",
  "degisiklikten sonra yine fallback"
)

-- async guard: an LSP answer arriving after an edit must not be cached
local guarded_calls = 0
local pending_done
package.loaded["unitykit.context.lsp"] = {
  resolve = function(_, _, done)
    guarded_calls = guarded_calls + 1
    pending_done = done
  end,
}
local buf2 = h.new_buf({ "public class B : MonoBehaviour", "{", "}" }, "cs")
h.eq(
  context.resolve(buf2, require("unitykit.config").setup()).source,
  "fallback",
  "pending sirasinda fallback"
)
h.check(cache.pending(buf2), "pending kaydi isaretli")

vim.api.nvim_buf_set_lines(
  buf2,
  0,
  -1,
  false,
  { "public class B : MonoBehaviour", "{", "  void Update() {}", "}" }
)
pending_done({
  class_name = "B",
  class_kind = "monobehaviour",
  class_range = { start_line = 0, end_line = 3 },
  method_ranges = {},
  implemented = {},
  source = "lsp",
})
h.eq(cache.get(buf2), nil, "duzenleme sonrasi gec gelen lsp yazilmaz")
h.eq(
  context.resolve(buf2, require("unitykit.config").setup()).source,
  "fallback",
  "gec lsp sonrasi yine fallback"
)
h.eq(guarded_calls, 2, "gecerli tick ile lsp yeniden tetiklenir")

-- done is idempotent: the first answer wins
local done = pending_done
done({
  class_name = "B",
  class_kind = "monobehaviour",
  class_range = { start_line = 0, end_line = 3 },
  method_ranges = {},
  implemented = {},
  source = "lsp",
})
done({
  class_name = "Z",
  class_kind = "monobehaviour",
  class_range = { start_line = 0, end_line = 3 },
  method_ranges = {},
  implemented = {},
  source = "lsp",
})
h.eq(cache.get(buf2).class_name, "B", "ikinci done yok sayilir")
h.eq(
  context.resolve(buf2, require("unitykit.config").setup()).source,
  "lsp",
  "gecerli lsp sonucu cache'te"
)
h.eq(guarded_calls, 2, "cache'te taze kayit varken lsp cagrilmaz")

-- invalid buffer never errors
cache.invalidate()
local invalid = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_delete(invalid, { force = true })
h.eq(cache.get(invalid), nil, "gecersiz buffer nil")
h.eq(cache.set(invalid, ctx), false, "gecersiz buffer set false")
h.eq(cache.pending(invalid), false, "gecersiz buffer pending false")

-- buffer cleanup: wiping a buffer drops its cache record
local buf3 = h.new_buf({ "public class C : MonoBehaviour", "{", "}" }, "cs")
cache.set(buf3, { class_name = "C", source = "fallback" })
vim.api.nvim_buf_delete(buf3, { force = true })
h.eq(cache.entries[buf3], nil, "wipeout cache kaydini siler")

-- ---------------------------------------------------------------------------
-- Cursor-dependent cache: nested and sibling classes, no edit between moves.
-- ---------------------------------------------------------------------------
local nested_lsp_calls = {}
package.loaded["unitykit.context.lsp"] = {
  resolve = function(bufnr, _, done)
    local fb = require("unitykit.context.fallback").resolve(bufnr)
    nested_lsp_calls[#nested_lsp_calls + 1] = fb.class_name
    done({
      class_name = fb.class_name,
      class_kind = fb.class_kind,
      class_range = fb.class_range,
      method_ranges = fb.method_ranges,
      implemented = fb.implemented,
      source = "lsp",
    })
  end,
}
package.loaded["unitykit.context"] = nil
local context2 = require("unitykit.context")

local nested = h.new_buf({
  "public class Outer : MonoBehaviour",          -- 0
  "{",                                           -- 1
  "    public class Inner : ScriptableObject",   -- 2
  "    {",                                       -- 3
  "    }",                                       -- 4
  "}",                                           -- 5
}, "cs")

-- Outer first
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local outer_ctx = context2.resolve(nested, require("unitykit.config").setup())
h.eq(outer_ctx.class_name, "Outer", "dis sinif secilir")
h.eq(outer_ctx.class_kind, "monobehaviour", "Outer kind")

-- Move to Inner without an edit: Inner's kind, not Outer's
vim.api.nvim_win_set_cursor(0, { 4, 8 })
local inner_ctx = context2.resolve(nested, require("unitykit.config").setup())
h.eq(inner_ctx.class_name, "Inner", "ic sinif secilir")
h.eq(inner_ctx.class_kind, "scriptableobject", "Inner kind")

-- Back to Outer without an edit: cached Outer kind, source lsp
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local outer_again = context2.resolve(nested, require("unitykit.config").setup())
h.eq(outer_again.class_name, "Outer", "geri Outer")
h.eq(outer_again.class_kind, "monobehaviour", "geri Outer kind")
h.eq(outer_again.source, "lsp", "cached kind source lsp")

-- same class at the same tick -> exactly one LSP request for Outer
local outer_calls = 0
for _, name in ipairs(nested_lsp_calls) do
  if name == "Outer" then
    outer_calls = outer_calls + 1
  end
end
h.eq(outer_calls, 1, "Outer icin tek LSP istegi")

-- two sibling classes in one file, no edit between resolves
local siblings = h.new_buf({
  "public class A : MonoBehaviour",    -- 0
  "{",                                 -- 1
  "}",                                 -- 2
  "public class B : ScriptableObject", -- 3
  "{",                                 -- 4
  "}",                                 -- 5
}, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
h.eq(
  context2.resolve(siblings, require("unitykit.config").setup()).class_kind,
  "monobehaviour",
  "kardes A kind"
)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
h.eq(
  context2.resolve(siblings, require("unitykit.config").setup()).class_kind,
  "scriptableobject",
  "kardes B kind"
)

h.finish()
