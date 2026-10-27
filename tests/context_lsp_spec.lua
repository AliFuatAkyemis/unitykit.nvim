local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local lsp = require("unitykit.context.lsp")

h.eq(lsp.parse_hover_class("```csharp\nclass UnityEngine.MonoBehaviour\n```\n  \nMonoBehaviour is a base class"), "UnityEngine.MonoBehaviour", "hover sinif adi")
h.eq(lsp.parse_hover_class("```csharp\nclass Deneme\n```"), "Deneme", "proje sinifi")
h.eq(lsp.parse_hover_class("```csharp\nstruct Vector3\n```"), nil, "struct degil")
h.eq(lsp.parse_hover_class(nil), nil, "nil guvenli")
h.eq(lsp.parse_hover_class("dokuman yok"), nil, "eslesme yok")

h.eq(lsp.parse_base_names("public class Deneme : MonoBehaviour"), { "MonoBehaviour" }, "tek base")
h.eq(lsp.parse_base_names("public class Deneme : MonoBehaviour, IFoo"), { "MonoBehaviour", "IFoo" }, "coklu base")
h.eq(lsp.parse_base_names("public class Foo<T> :"), {}, "cok satirli baslangic bos")
h.eq(lsp.parse_base_names("public class Plain"), {}, "base yok")
h.eq(
  lsp.parse_base_names("public class Foo : Base<int, string>, IFoo"),
  { "Base", "IFoo" },
  "generic base tek parca"
)
h.eq(
  lsp.parse_base_names("public class Foo<T> : Base where T : new()"),
  { "Base" },
  "where kisitlari atilir"
)

h.eq(lsp.strip_generics("Foo<T>"), "Foo", "generic temizle")
h.eq(lsp.strip_generics("Dictionary<int, string>"), "Dictionary", "coklu generic")
h.eq(lsp.strip_generics("MonoBehaviour"), "MonoBehaviour", "generic yok")

h.eq(lsp.normalize_method_name("Start() : void", nil), "Start", "detail bicimi")
h.eq(lsp.normalize_method_name("OnCollisionEnter(Collision)", "void"), "OnCollisionEnter", "parametreli")
h.eq(lsp.normalize_method_name("Update", "Update() : void"), "Update", "duz ad")
h.eq(lsp.qualify("monobehaviour"), "UnityEngine.MonoBehaviour", "qualify mono")
h.eq(lsp.qualify("editor"), "UnityEditor.Editor", "qualify editor")

-- no client: done(nil) immediately, no error
local buf = h.new_buf({ "class A : MonoBehaviour { }" }, "cs")
local called, result = 0, "sentinel"
lsp.resolve(buf, require("unitykit.config").setup({ timeout_ms = 50 }), function(ctx)
  called = called + 1
  result = ctx
end)
h.eq(called, 1, "client yokken done hemen cagrilir")
h.eq(result, nil, "client yokken nil")

h.finish()
