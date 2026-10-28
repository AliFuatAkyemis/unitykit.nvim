local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

-- Stub the LSP resolver before the context module loads; the fallback answer is
-- enough here and `-u NONE` has no client.
package.loaded["unitykit.context.lsp"] = { resolve = function() end }
package.loaded["unitykit.context"] = nil
local cmp_source = require("unitykit.completion.cmp")
local cfg = require("unitykit.config").setup({})

local dir = h.make_unity_project()
local buf = h.new_buf({
  "using UnityEngine;",                    -- 0
  "public class Player : MonoBehaviour",   -- 1
  "{",                                     -- 2
  "    void Start()",                      -- 3
  "    {",                                 -- 4
  "        // imleç burada",               -- 5
  "    }",                                 -- 6
  "}",                                     -- 7
}, "cs")
-- h.new_buf creates a scratch buffer (`buftype=nofile`); the source only runs
-- in regular file buffers.
vim.bo[buf].buftype = ""
vim.api.nvim_buf_set_name(buf, dir .. "/Assets/Player.cs")
vim.api.nvim_win_set_cursor(0, { 3, 4 })  -- sinif govdesi (0-based 2)

local items = cmp_source.items(buf, cfg)
h.check(#items > 0, "sinif govdesinde oneriler var")
local words = {}
for _, it in ipairs(items) do words[it.word] = true end
h.check(words.Awake, "Awake onerilir")
h.check(not words.Start, "mevcut Start gizlenir")
h.check(words.Update, "yazilmamis Update onerilir")
h.eq(items[1].detail, "Unity Message", "item detayi")

-- hide_implemented false
local all = cmp_source.items(buf, require("unitykit.config").setup({ hide_implemented = false }))
local has_start = false
for _, it in ipairs(all) do if it.word == "Start" then has_start = true end end
h.check(has_start, "hide_implemented false -> Start gorunur")

-- cfg.priority only reaches completion through sortText in `item.to_cmp_item`;
-- the source priority itself is configured by the user in cmp's `sources` list.
h.eq(all[1].sortText, "0" .. all[1].word, "priority sortText oncelik")
local no_priority = cmp_source.items(buf, require("unitykit.config").setup({ priority = false }))
h.eq(no_priority[1].sortText, nil, "priority false -> sortText yok")

-- cursor inside method body
vim.api.nvim_win_set_cursor(0, { 6, 8 })  -- 0-based 5, metot icinde
h.eq(cmp_source.items(buf, cfg), {}, "metot icinde bos")

-- non-C# filetype
vim.bo[buf].filetype = "lua"
h.eq(cmp_source.items(buf, cfg), {}, "cs olmayan filetype bos")
vim.bo[buf].filetype = "cs"

-- no Unity project
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "/Assets/Player.cs")
h.eq(cmp_source.items(buf, cfg), {}, "unity projesi yoksa bos")

-- scriptableobject gets its own set
vim.api.nvim_buf_set_name(buf, dir .. "/Assets/Data.cs")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "using UnityEngine;",                          -- 0
  "public class Data : ScriptableObject",        -- 1
  "{",                                           -- 2
  "}",                                           -- 3
})
vim.api.nvim_win_set_cursor(0, { 3, 4 })         -- 0-based 2
local so = cmp_source.items(buf, cfg)
local so_names = {}
for _, it in ipairs(so) do so_names[it.word] = true end
h.check(so_names.Reset, "scriptableobject Reset")
h.check(not so_names.Update, "scriptableobject Update yok")

-- register without cmp must not error
local ok, err = pcall(cmp_source.register, cfg)
h.check(ok, "cmp yokken register hata vermez: " .. tostring(err))

-- source table shape
local source = cmp_source.source
h.eq(source.get_trigger_characters(), {}, "tetikleyici karakter yok")
-- cmp invokes the callback with `:`; a plain `keyword_pattern` field is ignored.
h.eq(source:get_keyword_pattern(), [[\%([A-Za-z_][A-Za-z0-9_]*\)\?]], "keyword pattern")

-- scratch (nofile) buffers are skipped
local scratch = h.new_buf({
  "using UnityEngine;",
  "public class Scratch : MonoBehaviour",
  "{",
  "}",
}, "cs")
vim.api.nvim_buf_set_name(scratch, dir .. "/Assets/Scratch.cs")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
h.eq(cmp_source.items(scratch, cfg), {}, "scratch buffer bos")

-- non-Unity class inside a Unity project
local plain = h.new_buf({
  "public class Plain",
  "{",
  "}",
}, "cs")
vim.bo[plain].buftype = ""
vim.api.nvim_buf_set_name(plain, dir .. "/Assets/Plain.cs")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
h.eq(cmp_source.items(plain, cfg), {}, "unity sinifi olmayan baglam bos")

-- unmodifiable buffers are skipped
local locked = h.new_buf({
  "public class Locked : MonoBehaviour",
  "{",
  "}",
}, "cs")
vim.bo[locked].buftype = ""
vim.api.nvim_buf_set_name(locked, dir .. "/Assets/Locked.cs")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.bo[locked].modifiable = false
h.eq(cmp_source.items(locked, cfg), {}, "degistirilemez buffer bos")
vim.bo[locked].modifiable = true

-- is_available: word char immediately before the cursor
vim.api.nvim_set_current_buf(scratch)
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "        Aw" })
vim.api.nvim_win_set_cursor(0, { 1, 10 })
h.check(source.is_available(), "kelime karakterinden sonra available")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
h.check(not source.is_available(), "satir basinda available degil")
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "        _x" })
vim.api.nvim_win_set_cursor(0, { 1, 9 })
h.check(source.is_available(), "alt cizgi sonrasi available")

-- complete callback shape (never throws on an unusable buffer)
local result
local completed = pcall(source.complete, {}, function(response)
  result = response
end)
h.check(completed, "complete hata vermez")
h.eq(result, { items = {}, isIncomplete = false }, "complete bos yanit")

-- complete on the class body returns items
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].buftype = ""
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local body_result
source.complete({}, function(response)
  body_result = response
end)
h.check(body_result and #body_result.items > 0, "complete sinif govdesinde dolu")
h.eq(body_result and body_result.isIncomplete, false, "complete isIncomplete false")

-- cmp calls the source with `:` so the callback is the third argument
local colon_result
source:complete({}, function(response)
  colon_result = response
end)
h.check(colon_result and #colon_result.items > 0, "cmp cagri sekli de calisir")

-- register with a fake cmp module
local registrations = {}
package.loaded["cmp"] = {
  register_source = function(name, registered)
    registrations[#registrations + 1] = { name = name, source = registered }
  end,
}
local registered = cmp_source.register(require("unitykit.config").setup({ priority = false }))
h.check(registered, "cmp varken register true doner")
h.eq(#registrations, 1, "register cagrisi cmp'ye bir kez kaydeder")
h.eq(registrations[1] and registrations[1].name, "unitykit", "kaynak adi unitykit")
h.eq(registrations[1] and registrations[1].source, cmp_source.source,
  "source tablosu kaydedilir")

-- cursor inside a constructor body -> empty
local ctor = h.new_buf({
  "using UnityEngine;",                    -- 0
  "public class Enemy : MonoBehaviour",    -- 1
  "{",                                     -- 2
  "    public Enemy()",                    -- 3
  "    {",                                 -- 4
  "        _hp = 10;",                     -- 5
  "    }",                                 -- 6
  "}",                                     -- 7
}, "cs")
vim.bo[ctor].buftype = ""
vim.api.nvim_buf_set_name(ctor, dir .. "/Assets/Enemy.cs")
vim.api.nvim_win_set_cursor(0, { 6, 8 })  -- 0-based 5, inside constructor body
h.eq(cmp_source.items(ctor, cfg), {}, "constructor govdesinde bos")

-- cursor inside a block-bodied property setter -> empty
local prop = h.new_buf({
  "using UnityEngine;",                 -- 0
  "public class Prop : MonoBehaviour",  -- 1
  "{",                                  -- 2
  "    int _value;",                    -- 3
  "    public int Value",               -- 4
  "    {",                              -- 5
  "        get { return _value; }",     -- 6
  "        set { _value = value; }",    -- 7
  "    }",                              -- 8
  "}",                                  -- 9
}, "cs")
vim.bo[prop].buftype = ""
vim.api.nvim_buf_set_name(prop, dir .. "/Assets/Prop.cs")
vim.api.nvim_win_set_cursor(0, { 8, 12 })  -- 0-based 7, inside setter body
h.eq(cmp_source.items(prop, cfg), {}, "property setter govdesinde bos")

-- cursor inside a nested class -> that class's messages (non-empty)
local nested = h.new_buf({
  "using UnityEngine;",                          -- 0
  "public class Outer : MonoBehaviour",          -- 1
  "{",                                           -- 2
  "    public class Inner : ScriptableObject",   -- 3
  "    {",                                       -- 4
  "        // inside inner",                     -- 5
  "    }",                                       -- 6
  "}",                                           -- 7
}, "cs")
vim.bo[nested].buftype = ""
vim.api.nvim_buf_set_name(nested, dir .. "/Assets/Nested.cs")
vim.api.nvim_win_set_cursor(0, { 6, 8 })  -- 0-based 5, inside Inner body
local nested_items = cmp_source.items(nested, cfg)
h.check(#nested_items > 0, "nested sinif ici oneriler var")
local nested_words = {}
for _, it in ipairs(nested_items) do
  nested_words[it.word] = true
end
h.check(nested_words.Reset, "nested sinif kendi mesajlari (ScriptableObject Reset)")
h.check(not nested_words.Start, "nested sinifta MonoBehaviour Start yok")

h.finish()
