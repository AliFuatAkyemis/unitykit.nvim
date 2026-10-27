local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local fallback = require("unitykit.context.fallback")

h.eq(fallback.classify("MonoBehaviour"), "monobehaviour", "kisa ad mono")
h.eq(fallback.classify("UnityEngine.MonoBehaviour"), "monobehaviour", "tam ad mono")
h.eq(fallback.classify("UnityEditor.Editor"), "editor", "tam ad editor")
h.eq(fallback.classify("ScriptableObject"), "scriptableobject", "so")
h.eq(fallback.classify("Editor"), "editor", "kisa ad editor")
h.eq(fallback.classify("MyBase"), nil, "bilinmeyen nil")

local buf = h.new_buf({
  "using UnityEngine;",                       -- 0
  "",                                         -- 1
  "public class Deneme : MonoBehaviour",      -- 2
  "{",                                        -- 3
  "    [ContextMenu(\"x\")]",                 -- 4
  "    public void Start()",                  -- 5
  "    {",                                    -- 6
  "        Debug.Log(1);",                    -- 7
  "    }",                                    -- 8
  "",                                         -- 9
  "    void Update() { }",                    -- 10
  "}",                                        -- 11
}, "cs")
vim.api.nvim_win_set_cursor(0, { 4, 0 })

local ctx = fallback.resolve(buf)
h.eq(ctx.class_name, "Deneme", "sinif adi")
h.eq(ctx.class_kind, "monobehaviour", "sinif turu")
h.eq(ctx.source, "fallback", "kaynak fallback")
h.eq(ctx.class_range, { start_line = 2, end_line = 11 }, "sinif araligi")
h.check(ctx.implemented.Start, "Start mevcut")
h.check(ctx.implemented.Update, "Update mevcut")
h.check(not ctx.implemented.Awake, "Awake yok")
h.eq(#ctx.method_ranges, 2, "iki metot araligi")
h.eq(ctx.method_ranges[2], { start_line = 10, end_line = 10 }, "tek satir metot araligi")

-- nested class: cursor inner class
local nested = h.new_buf({
  "public class Outer : MonoBehaviour",  -- 0
  "{",                                   -- 1
  "    public class Inner : ScriptableObject", -- 2
  "    {",                               -- 3
  "        void Awake() { }",            -- 4
  "    }",                               -- 5
  "}",                                   -- 6
}, "cs")
vim.api.nvim_win_set_cursor(0, { 5, 8 })
h.eq(fallback.resolve(nested).class_name, "Inner", "en icteki sinif")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
h.eq(fallback.resolve(nested).class_name, "Outer", "dis sinif")

-- multi-line declaration and generic + multiple bases
local multi = h.new_buf({
  "public class Foo<T> :",               -- 0
  "    MonoBehaviour, IFoo",             -- 1
  "{",                                   -- 2
  "}",                                   -- 3
}, "cs")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local mctx = fallback.resolve(multi)
h.eq(mctx.class_name, "Foo", "generic sinif adi temiz")
h.eq(mctx.class_kind, "monobehaviour", "cok satirli base list")

-- class without base
local plain = h.new_buf({ "public class Plain", "{", "}" }, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local pctx = fallback.resolve(plain)
h.eq(pctx.class_kind, nil, "base yoksa tur yok")
h.eq(pctx.class_name, "Plain", "sinif adi yine bulunur")

-- cursor outside any class
local outside = h.new_buf({ "using UnityEngine;", "class A : MonoBehaviour { }" }, "cs")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
h.eq(fallback.resolve(outside).class_name, nil, "sinif disinda nil")

-- regression: one class, cursor above the declaration is still outside
local above = h.new_buf({
  "using UnityEngine;",
  "",
  "public class Solo : MonoBehaviour",
  "{",
  "}",
}, "cs")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
h.eq(fallback.resolve(above).class_name, nil, "bildirim ustunde sinif yok")

-- cursor after the last class body
local trailing = h.new_buf({
  "public class Finished : MonoBehaviour",
  "{",
  "}",
  "",
  "// trailing comment",
}, "cs")
vim.api.nvim_win_set_cursor(0, { 5, 0 })
h.eq(fallback.resolve(trailing).class_name, nil, "son siniftan sonra nil")

-- ---------------------------------------------------------------------------
-- Generic `where` constraints are not base lists or declarations.
-- ---------------------------------------------------------------------------
local constrained = h.new_buf({
  "public class Wrapper<T> where T : MonoBehaviour",
  "{",
  "}",
}, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local w = fallback.resolve(constrained)
h.eq(w.class_name, "Wrapper", "where sinif adi")
h.eq(w.class_kind, nil, "where base sayilmaz")

local two_where = h.new_buf({
  "public class Where<T>",         -- 0
  "    where T : MonoBehaviour",   -- 1
  "    where U : class",           -- 2
  "    where V : new()",           -- 3
  "{",                             -- 4
  "    void Awake() { }",          -- 5
  "}",                             -- 6
}, "cs")
vim.api.nvim_win_set_cursor(0, { 6, 4 })
local tw = fallback.resolve(two_where)
h.eq(tw.class_name, "Where", "cok where sinif adi")
h.eq(tw.class_kind, nil, "cok where base sayilmaz")
h.eq(tw.class_range, { start_line = 0, end_line = 6 }, "cok where sinif araligi")
h.check(tw.implemented.Awake, "cok where Awake")

-- ---------------------------------------------------------------------------
-- Method bodies, declaration lines and body-less methods.
-- ---------------------------------------------------------------------------
local methods = h.new_buf({
  "public class Methods : MonoBehaviour", -- 0
  "{",                                    -- 1
  "    public void Start()",              -- 2
  "    {",                                -- 3
  "        Helper();",                    -- 4
  "    }",                                -- 5
  "    public int Count() => 3;",         -- 6
  "    private void Helper() { }",        -- 7
  "    protected abstract void Gone();",  -- 8
  "}",                                    -- 9
}, "cs")
vim.api.nvim_win_set_cursor(0, { 5, 8 })
local m = fallback.resolve(methods)
h.eq(m.class_name, "Methods", "metot govdesi sinifi")
h.eq(#m.method_ranges, 4, "govdeli ifadeli ve abstract metotlar")
h.eq(m.method_ranges[1], { start_line = 2, end_line = 5 }, "metot govdesi araligi")
h.eq(m.method_ranges[2], { start_line = 6, end_line = 6 }, "ifade govdeli metot")
h.eq(m.method_ranges[3], { start_line = 7, end_line = 7 }, "tek satir govdeli metot")
h.eq(m.method_ranges[4], { start_line = 8, end_line = 8 }, "abstract metot")
h.check(m.implemented.Start, "Start govde araligi")
h.check(m.implemented.Count, "Count ifade govdeli")
h.check(m.implemented.Helper, "Helper mevcut")
h.check(m.implemented.Gone, "Gone abstract")
h.check(not m.implemented.Debug, "cagri metot sayilmaz")
h.check(not m.implemented.HelperCall, "yerel cagri metot sayilmaz")

-- method `where` constraints, tuple return types and finalizers
local where_method = h.new_buf({
  "public class WhereMethod : MonoBehaviour", -- 0
  "{",                                        -- 1
  "    public T Get<T>() where T : new()",    -- 2
  "    {",                                    -- 3
  "        return default(T);",               -- 4
  "    }",                                    -- 5
  "}",                                        -- 6
}, "cs")
vim.api.nvim_win_set_cursor(0, { 4, 8 })
local wm = fallback.resolve(where_method)
h.check(wm.implemented.Get, "where metot bulunur")
h.eq(#wm.method_ranges, 1, "where metot sayisi")
h.eq(wm.method_ranges[1], { start_line = 2, end_line = 5 }, "where metot govdesi")

local tuple = h.new_buf({
  "public class TupleReturn : MonoBehaviour", -- 0
  "{",                                        -- 1
  "    public (int, string) Get()",           -- 2
  "    {",                                    -- 3
  "        return (1, \"x\");",               -- 4
  "    }",                                    -- 5
  "}",                                        -- 6
}, "cs")
vim.api.nvim_win_set_cursor(0, { 4, 8 })
local tr = fallback.resolve(tuple)
h.check(tr.implemented.Get, "tuple donus tipi metot")
h.eq(#tr.method_ranges, 1, "tuple metot sayisi")
h.eq(tr.method_ranges[1], { start_line = 2, end_line = 5 }, "tuple metot govdesi")

local finalizer = h.new_buf({
  "public class Finalizer : MonoBehaviour", -- 0
  "{",                                      -- 1
  "    ~Finalizer()",                       -- 2
  "    {",                                  -- 3
  "    }",                                  -- 4
  "    void Start() { }",                   -- 5
  "}",                                      -- 6
}, "cs")
vim.api.nvim_win_set_cursor(0, { 6, 4 })
local fin = fallback.resolve(finalizer)
h.check(not fin.implemented.Finalizer, "finalizer metot degil")
h.check(fin.implemented.Start, "finalizer sinifinda Start")
h.eq(#fin.method_ranges, 1, "finalizer metot sayisi")

-- ---------------------------------------------------------------------------
-- Sibling classes and nested-class method isolation.
-- ---------------------------------------------------------------------------
local siblings = h.new_buf({
  "public class A : MonoBehaviour", -- 0
  "{",                              -- 1
  "    void Start() { }",           -- 2
  "}",                              -- 3
  "",                               -- 4
  "public class B : ScriptableObject", -- 5
  "{",                              -- 6
  "    void Awake() { }",           -- 7
  "}",                              -- 8
}, "cs")
vim.api.nvim_win_set_cursor(0, { 3, 4 })
local a = fallback.resolve(siblings)
h.eq(a.class_name, "A", "kardes sinif A")
h.eq(a.class_kind, "monobehaviour", "kardes sinif A turu")
vim.api.nvim_win_set_cursor(0, { 8, 4 })
local b = fallback.resolve(siblings)
h.eq(b.class_name, "B", "kardes sinif B")
h.eq(b.class_kind, "scriptableobject", "kardes sinif B turu")
h.check(b.implemented.Awake, "B Awake")
h.check(not b.implemented.Start, "B Start icermez")

local outer_methods = h.new_buf({
  "public class Outer : MonoBehaviour", -- 0
  "{",                                  -- 1
  "    public class Inner",             -- 2
  "    {",                              -- 3
  "        void Awake() { }",           -- 4
  "    }",                              -- 5
  "    void Start() { }",               -- 6
  "}",                                  -- 7
}, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local om = fallback.resolve(outer_methods)
h.eq(om.class_name, "Outer", "ic sinif bildirimi outer secer")
h.check(om.implemented.Start, "outer Start")
h.check(not om.implemented.Awake, "ic sinif metodu outer'a yazilmaz")
h.eq(#om.method_ranges, 1, "outer sadece kendi metodu")

-- ---------------------------------------------------------------------------
-- Multi-line declarations with generic and multiple bases.
-- ---------------------------------------------------------------------------
local multiline = h.new_buf({
  "public class Multi<T> :", -- 0
  "    MonoBehaviour,",      -- 1
  "    IFoo<T>,",            -- 2
  "    IBar",                -- 3
  "{",                       -- 4
  "    void Awake() { }",    -- 5
  "}",                       -- 6
}, "cs")
vim.api.nvim_win_set_cursor(0, { 6, 4 })
local ml = fallback.resolve(multiline)
h.eq(ml.class_name, "Multi", "cok satirli generic sinif")
h.eq(ml.class_kind, "monobehaviour", "cok satirli ilk base")
h.eq(ml.class_range, { start_line = 0, end_line = 6 }, "cok satirli sinif araligi")
h.check(ml.implemented.Awake, "cok satirli Awake")

-- ---------------------------------------------------------------------------
-- Attributed methods (same line and separate line).
-- ---------------------------------------------------------------------------
local attributed = h.new_buf({
  "public class Attributed : MonoBehaviour", -- 0
  "{",                                       -- 1
  "    [ContextMenu(\"x\")]",                -- 2
  "    [Range(0, 1)]",                       -- 3
  "    public void Start()",                 -- 4
  "    {",                                   -- 5
  "    }",                                   -- 6
  "",                                        -- 7
  "    [Header(\"y\")] public void Awake() { }", -- 8
  "}",                                       -- 9
}, "cs")
vim.api.nvim_win_set_cursor(0, { 6, 4 })
local at = fallback.resolve(attributed)
h.check(at.implemented.Start, "nitelikli Start")
h.check(at.implemented.Awake, "ayni satir nitelikli Awake")
h.check(not at.implemented.ContextMenu, "ContextMenu metot degil")
h.check(not at.implemented.Range, "Range metot degil")
h.check(not at.implemented.Header, "Header metot degil")
h.eq(#at.method_ranges, 2, "nitelikli metot sayisi")

-- ---------------------------------------------------------------------------
-- Comments and strings must not create classes or methods.
-- ---------------------------------------------------------------------------
local guarded = h.new_buf({
  "// public class Fake : MonoBehaviour",              -- 0
  "/* public class Block : MonoBehaviour */",         -- 1
  "string s = \"public class InString : MonoBehaviour\";", -- 2
  "public class Real : MonoBehaviour",                -- 3
  "{",                                                -- 4
  "    // void Awake() { }",                          -- 5
  "    string t = \"void Start() { }\";",             -- 6
  "    void Update() { }",                            -- 7
  "}",                                                -- 8
}, "cs")
vim.api.nvim_win_set_cursor(0, { 8, 4 })
local g = fallback.resolve(guarded)
h.eq(g.class_name, "Real", "yorum ve string sinif sayilmaz")
h.check(not g.implemented.Awake, "yorumdaki metot sayilmaz")
h.check(not g.implemented.Start, "stringdeki metot sayilmaz")
h.check(g.implemented.Update, "gercek metot bulunur")
h.eq(#g.method_ranges, 1, "tek gercek metot")

-- ---------------------------------------------------------------------------
-- Defensive behaviour for odd input.
-- ---------------------------------------------------------------------------
local empty = h.new_buf({}, "cs")
local e = fallback.resolve(empty)
h.eq(e.class_name, nil, "bos buffer sinif yok")
h.eq(e.class_kind, nil, "bos buffer tur yok")
h.eq(e.class_range, nil, "bos buffer aralik yok")
h.eq(e.method_ranges, {}, "bos buffer metot yok")
h.eq(e.implemented, {}, "bos buffer implemented bos")
h.eq(e.source, "fallback", "bos buffer kaynak")

local unbalanced = h.new_buf({ "public class Broken : MonoBehaviour", "{", "void Start() {" }, "cs")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local ok, br = pcall(fallback.resolve, unbalanced)
h.check(ok, "dengesiz brace hata vermez")
h.eq(type(br), "table", "dengesiz brace tablo doner")
h.eq(br.source, "fallback", "dengesiz brace kaynak")

local invalid_ok, invalid = pcall(fallback.resolve, 99999)
h.check(invalid_ok, "gecersiz buffer hata vermez")
h.eq(invalid.source, "fallback", "gecersiz buffer kaynak")
h.eq(invalid.class_name, nil, "gecersiz buffer sinif yok")

h.eq(fallback.classify(nil), nil, "nil isim nil")

-- Large-buffer regression: 400 methods are all found in one resolve.
local many_lines = { "public class Many : MonoBehaviour", "{" }
for i = 1, 400 do
  many_lines[#many_lines + 1] = string.format("    void M%d() { }", i)
end
many_lines[#many_lines + 1] = "}"
local many = h.new_buf(many_lines, "cs")
vim.api.nvim_win_set_cursor(0, { 3, 4 })
local many_ctx = fallback.resolve(many)
h.eq(#many_ctx.method_ranges, 400, "400 metot cozulur")
h.check(many_ctx.implemented.M400, "son metot kaydedilir")

h.finish()
