local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local lsp = require("unitykit.context.lsp")

h.eq(
  lsp.parse_hover_class(
    "```csharp\nclass UnityEngine.MonoBehaviour\n```\n  \nMonoBehaviour is a base class"
  ),
  "UnityEngine.MonoBehaviour",
  "hover sinif adi"
)
h.eq(lsp.parse_hover_class("```csharp\nclass Deneme\n```"), "Deneme", "proje sinifi")
h.eq(lsp.parse_hover_class("```csharp\nstruct Vector3\n```"), nil, "struct degil")
h.eq(lsp.parse_hover_class(nil), nil, "nil guvenli")
h.eq(lsp.parse_hover_class("dokuman yok"), nil, "eslesme yok")

h.eq(lsp.parse_base_names("public class Deneme : MonoBehaviour"), { "MonoBehaviour" }, "tek base")
h.eq(
  lsp.parse_base_names("public class Deneme : MonoBehaviour, IFoo"),
  { "MonoBehaviour", "IFoo" },
  "coklu base"
)
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
h.eq(
  lsp.parse_base_names("public class Foo : MonoBehaviour // yorum"),
  { "MonoBehaviour" },
  "satir yorumu atilir"
)
h.eq(
  lsp.parse_base_names("public class Foo : Base /* yorum */, IFoo"),
  { "Base", "IFoo" },
  "blok yorumu atilir"
)

h.eq(lsp.strip_generics("Foo<T>"), "Foo", "generic temizle")
h.eq(lsp.strip_generics("Dictionary<int, string>"), "Dictionary", "coklu generic")
h.eq(lsp.strip_generics("MonoBehaviour"), "MonoBehaviour", "generic yok")

h.eq(lsp.normalize_method_name("Start() : void", nil), "Start", "detail bicimi")
h.eq(
  lsp.normalize_method_name("OnCollisionEnter(Collision)", "void"),
  "OnCollisionEnter",
  "parametreli"
)
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

-- async path with a fake client (answers documentSymbol and hover)
local real_get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function()
  return {
    {
      server_capabilities = { workspaceSymbolProvider = false },
      request = function(_, method, _, handler)
        if method == "textDocument/documentSymbol" then
          handler(nil, {
            {
              name = "Player",
              kind = 5,
              range = {
                start = { line = 1, character = 0 },
                ["end"] = { line = 4, character = 1 },
              },
              children = {
                {
                  name = "Start() : void",
                  detail = "",
                  kind = 6,
                  range = {
                    start = { line = 3, character = 4 },
                    ["end"] = { line = 3, character = 10 },
                  },
                },
              },
            },
          })
        elseif method == "textDocument/hover" then
          handler(nil, {
            contents = {
              kind = "markdown",
              value = "```csharp\nclass UnityEngine.MonoBehaviour\n```",
            },
          })
        end
      end,
    },
  }
end
local async_buf = h.new_buf({
  "using UnityEngine;",                       -- 0
  "public class Player : MonoBehaviour",      -- 1
  "{",                                        -- 2
  "    void Start() { }",                     -- 3
  "}",                                        -- 4
}, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local async_calls, async_ctx = 0, "sentinel"
local ok, err = pcall(
  lsp.resolve,
  async_buf,
  require("unitykit.config").setup({ timeout_ms = 500 }),
  function(ctx)
    async_calls = async_calls + 1
    async_ctx = ctx
  end
)
vim.wait(500, function()
  return async_calls > 0
end)
vim.lsp.get_clients = real_get_clients
h.check(ok, "async resolve hata vermez")
if not ok then
  print("  error: " .. tostring(err))
end
h.eq(async_calls, 1, "async done tam bir kez")
h.eq(async_ctx and async_ctx.class_kind, "monobehaviour", "async sinif turu")
h.eq(async_ctx and async_ctx.source, "lsp", "async kaynak lsp")
h.eq(
  async_ctx and async_ctx.class_range,
  { start_line = 1, end_line = 4 },
  "async sinif araligi"
)
h.check(async_ctx and async_ctx.implemented.Start, "async Start mevcut")

-- namespace-qualified base: the last segment is queried and the symbol with a
-- matching containerName is preferred over an earlier same-named symbol.
local right_file = vim.fn.tempname() .. "_Right.cs"
local wrong_file = vim.fn.tempname() .. "_Wrong.cs"
do
  local f = io.open(right_file, "w")
  f:write("public class BaseEnemy : MonoBehaviour\n{\n}\n")
  f:close()
  f = io.open(wrong_file, "w")
  f:write("public class BaseEnemy : ScriptableObject\n{\n}\n")
  f:close()
end
local right_uri = vim.uri_from_fname(right_file)
local wrong_uri = vim.uri_from_fname(wrong_file)

local workspace_query
vim.lsp.get_clients = function()
  return {
    {
      server_capabilities = { workspaceSymbolProvider = true },
      request = function(_, method, params, handler)
        if method == "textDocument/documentSymbol" then
          handler(nil, {
            {
              name = "Foo",
              kind = 5,
              range = {
                start = { line = 0, character = 0 },
                ["end"] = { line = 2, character = 1 },
              },
            },
          })
        elseif method == "textDocument/hover" then
          handler(nil, {
            contents = {
              kind = "markdown",
              value = "```csharp\nclass Game.BaseEnemy\n```",
            },
          })
        elseif method == "workspace/symbol" then
          workspace_query = params.query
          handler(nil, {
            {
              name = "BaseEnemy",
              kind = 5,
              containerName = "Wrong",
              location = {
                uri = wrong_uri,
                range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { line = 0, character = 10 },
                },
              },
            },
            {
              name = "BaseEnemy",
              kind = 5,
              containerName = "Game",
              location = {
                uri = right_uri,
                range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { line = 0, character = 10 },
                },
              },
            },
          })
        end
      end,
    },
  }
end
local ns_buf = h.new_buf({
  "public class Foo : Game.BaseEnemy", -- 0
  "{",                                 -- 1
  "}",                                 -- 2
}, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local ns_calls, ns_ctx = 0, "sentinel"
local ns_ok = pcall(
  lsp.resolve,
  ns_buf,
  require("unitykit.config").setup({ timeout_ms = 500 }),
  function(ctx)
    ns_calls = ns_calls + 1
    ns_ctx = ctx
  end
)
vim.wait(500, function()
  return ns_calls > 0
end)
vim.lsp.get_clients = real_get_clients
h.check(ns_ok, "namespace resolve hata vermez")
h.eq(workspace_query, "BaseEnemy", "sorgu son segment")
h.eq(ns_calls, 1, "namespace done tam bir kez")
h.eq(ns_ctx and ns_ctx.class_kind, "monobehaviour", "namespace base cozulur")

h.finish()
