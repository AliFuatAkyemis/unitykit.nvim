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

h.finish()
