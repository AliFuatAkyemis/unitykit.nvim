# unitykit.nvim Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** C# dosyalarında sınıf türüne uygun Unity mesajlarını (`Awake`, `Start`, `Update`, `OnCollisionEnter`, Editor override'ları) `nvim-cmp` üzerinden snippet olarak tamamlayan Neovim eklentisi.

**Architecture:** LSP-first hibrit. `textDocument/documentSymbol` sınıf/metot sınırlarını verir; `hover` + `workspace/symbol` kalıtım zincirini çözer. LSP yoksa veya `timeout_ms` aşılırsa regex fallback anında döner, LSP sonucu arka planda cache'e yazılır. Mesaj verisi bundled Lua tablolarıdır.

**Tech Stack:** Lua 5.x (LuaJIT), Neovim >= 0.10 API (`vim.lsp`, `vim.snippet`, `vim.fs`), `nvim-cmp` source API, headless Neovim test harness (`nvim -l`).

**Spec:** `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md`

## Global Constraints

- Neovim >= 0.10 zorunlu; `vim.snippet` ve `vim.lsp.get_clients` kullanılabilir varsayılır.
- Tek zorunlu paket bağımlılığı `hrsh7th/nvim-cmp`. LuaSnip, treesitter, Mason, Neovide, nvim-lspconfig **kullanılmaz**.
- Unity kurulumu gerekmez; mesajlar bundled.
- Lua modül adı `unitykit`; dosyalar `lua/unitykit/` altında.
- Girinti 2 boşluk, `stylua.toml` kuralları, satır genişliği 100.
- Satır numaraları içeride **0-based**, test fixture'larında da 0-based.
- Testler `-u NONE` ile, repo kökünden, Unity/LSP olmadan çalışır.
- Varsayılanlar: `filetypes = { "cs" }`, `body = "block"`, `access = "none"`, `hide_implemented = true`, `priority = true`, `timeout_ms = 1500`.
- Snippet imleç yer tutucusu `$0`; girinti `vim.snippet` tarafından uygulanır, eklenti boşluk eklemez.
- Hiçbir modül `require("cmp")` çağrısını modül yüklenirken yapmaz (test ve `-u NONE` uyumu); yalnız `completion/cmp.lua` kayıt sırasında `pcall` ile yapar.
- `nvim-cmp` yoksa eklenti hata vermez, sessizce devre dışı kalır.

## Review Focus

- **İmleç metot gövdesi içindeyken:** öneri listesi boş olmalı; sınıf gövdesi kontrolü metot aralıklarını dışlamalı.
- **Tek dosyada birden fazla sınıf / iç içe sınıf:** imleci içeren **en içteki** sınıf seçilmeli; dış sınıfın mesajları sızmamalı.
- **Çok satırlı sınıf bildirimi** (`class Foo :` + satır sonu + `MonoBehaviour`): fallback base list'i yakalamalı.
- **Attribute ve modifier'lı metotlar** (`[ContextMenu("x")] public void Start()`): mevcut metot filtresi `Start`'ı tanımalı.
- **Generic sınıf ve çoklu base** (`class Foo<T> : MonoBehaviour, IFoo`): base list'in **ilk** öğesi kullanılmalı, generic parametreler isimden ayıklanmalı.

---

### Task 1: Test harness + config

**Files:**
- Create: `tests/helpers.lua`
- Create: `tests/run.sh`
- Create: `lua/unitykit/config.lua`
- Test: `tests/config_spec.lua`

**Interfaces:**
- Consumes: yok
- Produces:
  - `require("unitykit.config").defaults -> table`
  - `require("unitykit.config").setup(opts: table|nil) -> Config`
  - `Config` alanları: `filetypes: string[]`, `body: "block"|"line"`, `access: "none"|"private"|"public"|"protected"`, `hide_implemented: boolean`, `priority: boolean`, `timeout_ms: integer`
  - `tests/helpers.lua`: `check(cond, label)`, `eq(actual, expected, label)`, `finish()`, `new_buf(lines, filetype) -> integer`, `make_unity_project() -> string`

- [ ] **Step 1: Write `tests/run.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for spec in tests/*_spec.lua; do
  echo "== $spec"
  nvim --headless -u NONE -l "$spec" || status=1
done
exit "$status"
```

`chmod +x tests/run.sh`.

- [ ] **Step 2: Write `tests/helpers.lua`**

Functions:

- `check(cond, label)` -> prints `ok   - label` / `FAIL - label`, increments counters.
- `eq(actual, expected, label)` -> compares with `vim.deep_equal`, prints actual/expected on failure.
- `finish()` -> prints `N passed, M failed`, `os.exit(M == 0 and 0 or 1)`.
- `new_buf(lines, filetype)` -> `nvim_create_buf(false, true)`, sets lines, `nvim_set_current_buf`, `vim.bo.filetype = filetype or "cs"`, cursor `(1, 0)`, returns bufnr.
- `make_unity_project()` -> temp dir (`vim.fn.tempname()`), `mkdir -p` `Assets/` and `ProjectSettings/`, writes `ProjectSettings/ProjectVersion.txt` with `m_EditorVersion: 6000.0.0f1`, returns absolute path.

Each spec starts with:

```lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")
```

- [ ] **Step 3: Write failing `tests/config_spec.lua`**

```lua
local cfg = require("unitykit.config")

h.eq(cfg.setup(), {
  filetypes = { "cs" }, body = "block", access = "none",
  hide_implemented = true, priority = true, timeout_ms = 1500,
}, "setup() varsayilanlari dondurur")

h.eq(cfg.setup({ body = "line", access = "public" }).access, "public", "override uygulanir")
h.eq(cfg.setup({ body = "line" }).body, "line", "body line")

h.eq(cfg.setup({ body = "nope" }).body, "block", "gecersiz body -> block")
h.eq(cfg.setup({ access = "nope" }).access, "none", "gecersiz access -> none")

local notified = {}
local orig = vim.notify
vim.notify = function(msg) notified[#notified + 1] = msg end
cfg.setup({ body = "nope" })
vim.notify = orig
h.check(#notified == 1, "gecersiz ayar icin tek uyari")

local user = { body = "line" }
cfg.setup(user)
h.eq(user, { body = "line" }, "kullanici tablosu degistirilmez")

h.eq(cfg.setup({ filetypes = { "cs", "razor" } }).filetypes, { "cs", "razor" }, "filetypes kopyalanir")
```

- [ ] **Step 4: Run test, verify fail**

Run: `nvim --headless -u NONE -l tests/config_spec.lua`
Expected: FAIL — module `unitykit.config` not found.

- [ ] **Step 5: Implement `lua/unitykit/config.lua`**

- `M.defaults` sabit tablo (yukarıdaki değerler).
- `M.setup(opts)` -> yeni tablo üretir: `vim.tbl_deep_extend("force", {}, M.defaults, opts or {})`.
- Doğrulama: `body` ve `access` beyaz listesi; geçersizse varsayılan + `vim.notify("unitykit: invalid <key> ...", vim.log.levels.WARN)`.
- `timeout_ms` sayı değilse varsayılan.
- Sonuç tablosunu ve `filetypes` dizisini kopyalar; kullanıcı tablosuna yazmaz.
- Modül içinde `M.current` tutulur (`setup` son çağrısı); `M.get()` -> `M.current or M.setup()`.

- [ ] **Step 6: Run tests, verify pass**

Run: `nvim --headless -u NONE -l tests/config_spec.lua`
Expected: `FAIL` satırı yok, exit 0.

- [ ] **Step 7: Commit**

```bash
git add tests/run.sh tests/helpers.lua tests/config_spec.lua lua/unitykit/config.lua
git commit -m "feat: add config module and headless test harness"
```

---

### Task 2: Unity project detection

**Files:**
- Create: `lua/unitykit/project.lua`
- Test: `tests/project_spec.lua`

**Interfaces:**
- Consumes: yok
- Produces:
  - `require("unitykit.project").root(bufnr: integer) -> string|nil` — absolute path, trailing slash yok
  - `require("unitykit.project").reset(bufnr: integer|nil)` — nil ise tüm cache
  - `require("unitykit.project").is_unity_root(dir: string) -> boolean`

- [ ] **Step 1: Write failing `tests/project_spec.lua`**

Cases:

```lua
local project = require("unitykit.project")

local dir = h.make_unity_project()
local buf = h.new_buf({ "public class A {}" }, "cs")
vim.api.nvim_buf_set_name(buf, dir .. "/Assets/Scripts/A.cs")
h.eq(project.root(buf), dir, "Assets + ProjectVersion -> kok")

-- nested 3 levels
local deep = dir .. "/Assets/Scripts/Sub/Deep/B.cs"
vim.fn.mkdir(vim.fn.fnamemodify(deep, ":h"), "p")
vim.api.nvim_buf_set_name(buf, deep)
h.eq(project.root(buf), dir, "ust dizinlere yurur")

-- only Assets, no ProjectVersion
local fake = vim.fn.tempname()
vim.fn.mkdir(fake .. "/Assets", "p")
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

h.check(project.is_unity_root(dir), "is_unity_root dogru")
h.check(not project.is_unity_root(fake), "is_unity_root eksik kokte false")
```

- [ ] **Step 2: Run, verify fail** — `nvim --headless -u NONE -l tests/project_spec.lua` -> module not found.

- [ ] **Step 3: Implement `lua/unitykit/project.lua`**

- `is_unity_root(dir)`: `vim.fn.isdirectory(dir .. "/Assets") == 1` **ve** `vim.fn.filereadable(dir .. "/ProjectSettings/ProjectVersion.txt") == 1`.
- `root(bufnr)`: cache anahtarı `bufnr`, değer `{ name = buf name, root = path|nil }`; isim değiştiyse yeniden hesapla. `vim.fs.dirname` ile yukarı yürü, 64 seviye sınırı, `/` kökünde dur.
- `reset(bufnr)`: verilen kaydı veya tüm cache'i sil.
- `BufWipeout` için autocmd **kaydetme** (context cache sahibi temizler); `project` sadece isim karşılaştırmasıyla kendini korur.

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add lua/unitykit/project.lua tests/project_spec.lua
git commit -m "feat: detect Unity project root"
```

---

### Task 3: Message tables and query API

**Files:**
- Create: `lua/unitykit/messages/init.lua`
- Create: `lua/unitykit/messages/monobehaviour.lua`
- Create: `lua/unitykit/messages/scriptableobject.lua`
- Create: `lua/unitykit/messages/editor.lua`
- Test: `tests/messages_spec.lua`

**Interfaces:**
- Consumes: yok
- Produces:
  - `require("unitykit.messages").get(kind: string) -> Message[]` (kopya değil, salt-okunur kabul edilir)
  - `require("unitykit.messages").get_by_name(kind: string, name: string) -> Message|nil`
  - `require("unitykit.messages").kinds -> { "monobehaviour", "scriptableobject", "editor" }`
  - `Message` alanları: `name: string`, `params: string|nil`, `returns: string|nil`, `modifiers: string|nil`, `doc: string`

- [ ] **Step 1: Write failing `tests/messages_spec.lua`**

```lua
local messages = require("unitykit.messages")

h.eq(messages.kinds, { "monobehaviour", "scriptableobject", "editor" }, "tur sirasi")

local mono = messages.get("monobehaviour")
local names = {}
for _, m in ipairs(mono) do names[m.name] = true end

for _, expected in ipairs({
  "Awake", "OnEnable", "Start", "FixedUpdate", "Update", "LateUpdate",
  "OnDisable", "OnDestroy", "OnValidate", "Reset",
  "OnCollisionEnter", "OnCollisionStay", "OnCollisionExit",
  "OnTriggerEnter", "OnTriggerStay", "OnTriggerExit",
  "OnControllerColliderHit", "OnParticleCollision",
  "OnMouseEnter", "OnMouseOver", "OnMouseExit", "OnMouseDown", "OnMouseUp",
  "OnMouseUpAsButton", "OnMouseDrag",
  "OnGUI", "OnDrawGizmos", "OnDrawGizmosSelected",
  "OnBecameVisible", "OnBecameInvisible",
  "OnApplicationFocus", "OnApplicationPause", "OnApplicationQuit",
  "OnTransformChildrenChanged", "OnTransformParentChanged",
  "OnAudioFilterRead",
}) do h.check(names[expected], "mono icinde " .. expected) end

h.eq(messages.get_by_name("monobehaviour", "OnCollisionEnter").params, "Collision collision", "collision imzasi")
h.eq(messages.get_by_name("monobehaviour", "OnTriggerEnter").params, "Collider other", "trigger imzasi")
h.eq(messages.get_by_name("monobehaviour", "OnMouseDown").params, nil, "parametresiz mesaj")
h.eq(messages.get_by_name("monobehaviour", "OnApplicationFocus").params, "bool hasFocus", "bool parametre")

local so = {}
for _, m in ipairs(messages.get("scriptableobject")) do so[m.name] = true end
h.check(so.Reset, "scriptableobject Reset var")
h.check(not so.Update, "scriptableobject Update yok")

local editor = messages.get("editor")
h.check(#editor > 0, "editor listesi bos degil")
for _, m in ipairs(editor) do
  h.eq(m.modifiers, "public override", "editor modifiers: " .. m.name)
end
h.eq(messages.get_by_name("editor", "HasPreviewGUI").returns, "bool", "HasPreviewGUI bool doner")
h.eq(messages.get_by_name("editor", "RequiresConstantRepaint").returns, "bool", "RequiresConstantRepaint bool doner")
h.eq(messages.get_by_name("editor", "OnPreviewGUI").params, "Rect r, GUIStyle background", "OnPreviewGUI imzasi")

h.eq(messages.get("nope"), {}, "bilinmeyen tur bos liste")
h.eq(messages.get_by_name("nope", "Start"), nil, "bilinmeyen tur nil")

local seen = {}
for _, m in ipairs(mono) do
  h.check(not seen[m.name], "tekrar yok: " .. m.name)
  seen[m.name] = true
end
for kind, list in pairs({ monobehaviour = mono, scriptableobject = messages.get("scriptableobject"), editor = editor }) do
  for _, m in ipairs(list) do
    h.check(type(m.doc) == "string" and #m.doc > 0, "doc dolu: " .. kind .. "." .. m.name)
  end
end
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement the four message files**

`monobehaviour.lua`, `scriptableobject.lua`, `editor.lua` her biri şu biçimde bir dizi döndürür (`return { ... }`):

```lua
{ name = "Start", doc = "İlk karede, Update'ten önce bir kez çağrılır." },
{ name = "OnCollisionEnter", params = "Collision collision", doc = "..." },
{ name = "OnInspectorGUI", modifiers = "public override", doc = "..." },
{ name = "HasPreviewGUI", returns = "bool", modifiers = "public override", doc = "..." },
```

Tam listeler ve imzalar spec §6.2'de. `modifiers` yalnız `editor` setinde dolu. `doc` tek satır, Türkçe, mesajın ne zaman çağrıldığını söyler.

`messages/init.lua`:

- `M.kinds` sabit dizi.
- `M.sets` = `{ monobehaviour = require(...), ... }`, dosya yüklenirken bir kez.
- `M.get(kind)` -> `M.sets[kind] or {}`.
- `M.get_by_name(kind, name)` -> doğrusal arama (liste küçük).

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add lua/unitykit/messages tests/messages_spec.lua
git commit -m "feat: add bundled Unity message tables"
```

---

### Task 4: Snippet and cmp item rendering

**Files:**
- Create: `lua/unitykit/completion/item.lua`
- Test: `tests/completion_spec.lua`

**Interfaces:**
- Consumes: `Message` (Task 3), `Config` (Task 1)
- Produces:
  - `require("unitykit.completion.item").render(msg: Message, cfg: Config) -> string` — LSP snippet metni, `$0` dahil
  - `require("unitykit.completion.item").to_cmp_item(msg: Message, cfg: Config, ctx: table|nil) -> table` — `word`, `label`, `kind = 15`, `insertTextFormat = 2`, `insertText`, `detail = "Unity Message"`, `documentation`, `sortText`, `filterText`
  - `require("unitykit.completion.item").KIND_SNIPPET = 15`, `FORMAT_SNIPPET = 2`

- [ ] **Step 1: Write failing `tests/completion_spec.lua`**

```lua
local item = require("unitykit.completion.item")
local cfg = require("unitykit.config").setup({})

local start = { name = "Start", doc = "Ilk karede cagrilir." }
h.eq(item.render(start, cfg), "void Start()\n{\n    $0\n}", "blok govde")

local line_cfg = require("unitykit.config").setup({ body = "line" })
h.eq(item.render(start, line_cfg), "void Start() { $0 }", "tek satir govde")

h.eq(item.render(start, require("unitykit.config").setup({ access = "private" })),
  "private void Start()\n{\n    $0\n}", "private erisim")

local collision = { name = "OnCollisionEnter", params = "Collision collision", doc = "..." }
h.eq(item.render(collision, cfg), "void OnCollisionEnter(Collision collision)\n{\n    $0\n}", "parametreli imza")

local inspector = { name = "OnInspectorGUI", modifiers = "public override", doc = "..." }
h.eq(item.render(inspector, cfg), "public override void OnInspectorGUI()\n{\n    $0\n}", "override erisimi ezer")

-- modifiers access ayarini ezmeli
h.eq(item.render(inspector, require("unitykit.config").setup({ access = "private" })),
  "public override void OnInspectorGUI()\n{\n    $0\n}", "modifiers access'i ezer")

local preview = { name = "HasPreviewGUI", returns = "bool", modifiers = "public override", doc = "..." }
h.eq(item.render(preview, cfg), "public override bool HasPreviewGUI()\n{\n    $0\n}", "bool donus")

local cmp_item = item.to_cmp_item(start, cfg)
h.eq(cmp_item.word, "Start", "word")
h.eq(cmp_item.label, "Start()", "label")
h.eq(cmp_item.kind, 15, "kind Snippet")
h.eq(cmp_item.insertTextFormat, 2, "insertTextFormat Snippet")
h.eq(cmp_item.detail, "Unity Message", "detail")
h.eq(cmp_item.sortText, "0Start", "sortText oncelik")
h.eq(cmp_item.filterText, "Start", "filterText")
h.check(cmp_item.documentation.value:find("Start", 1, true) ~= nil, "dokuman mesaj adini icerir")
h.check(cmp_item.documentation.value:find("void Start()", 1, true) ~= nil, "dokuman imzayi icerir")

local no_priority = item.to_cmp_item(start, require("unitykit.config").setup({ priority = false }))
h.eq(no_priority.sortText, nil, "priority false -> sortText yok")

h.eq(item.render({ name = "X", doc = "" }, require("unitykit.config").setup({ access = "protected" })),
  "protected void X()\n{\n    $0\n}", "protected erisim")
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement `lua/unitykit/completion/item.lua`**

- `ACCESS = { none = "", private = "private ", public = "public ", protected = "protected " }`.
- `signature(msg, cfg)`: `(msg.modifiers or ACCESS[cfg.access]) .. (msg.returns and (msg.returns .. " ") or "void ") .. msg.name .. "(" .. (msg.params or "") .. ")"`.
- `render`: block -> `sig .. "\n{\n    $0\n}"`; line -> `sig .. " { $0 }"`.
- `to_cmp_item`: tablo yukarıdaki alanlarla; `documentation = { kind = "markdown", value = "**" .. name .. "** — " .. doc .. "\n\n```csharp\n" .. signature .. "\n```" }`; `sortText = cfg.priority and ("0" .. msg.name) or nil`.
- `ctx` parametresi şimdilik kullanılmaz; `---@param ctx table|nil` olarak imzada kalır (Task 8 kullanacak).

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add lua/unitykit/completion/item.lua tests/completion_spec.lua
git commit -m "feat: render Unity message snippets as cmp items"
```

---

### Task 5: Regex fallback context

**Files:**
- Create: `lua/unitykit/context/fallback.lua`
- Test: `tests/context_spec.lua`

**Interfaces:**
- Consumes: yok (saf buffer okuma)
- Produces:
  - `require("unitykit.context.fallback").resolve(bufnr: integer) -> Context`
  - `require("unitykit.context.fallback").classify(name: string) -> string|nil` (`"monobehaviour"|"scriptableobject"|"editor"`)
  - `Context` alanları: `class_name: string|nil`, `class_kind: string|nil`, `class_range: {start_line: integer, end_line: integer}|nil`, `method_ranges: {start_line: integer, end_line: integer}[]`, `implemented: table<string, true>`, `source = "fallback"`
  - Satırlar **0-based**, `end_line` **dahil**.

- [ ] **Step 1: Write failing `tests/context_spec.lua`**

```lua
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
local mctx = fallback.resolve(multi)
h.eq(mctx.class_name, "Foo", "generic sinif adi temiz")
h.eq(mctx.class_kind, "monobehaviour", "cok satirli base list")

-- class without base
local plain = h.new_buf({ "public class Plain", "{", "}" }, "cs")
local pctx = fallback.resolve(plain)
h.eq(pctx.class_kind, nil, "base yoksa tur yok")
h.eq(pctx.class_name, "Plain", "sinif adi yine bulunur")

-- cursor outside any class
local outside = h.new_buf({ "using UnityEngine;", "class A : MonoBehaviour { }" }, "cs")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
h.eq(fallback.resolve(outside).class_name, nil, "sinif disinda nil")
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement `lua/unitykit/context/fallback.lua`**

Algorithm:

1. `lines = nvim_buf_get_lines(bufnr, 0, -1, false)`, `text = table.concat(lines, "\n")`.
2. Cursor byte offset: `row = nvim_win_get_cursor(0)[1] - 1`, `offset = sum(#lines[i] + 1 for i < row) + col`.
3. Find every class declaration with `("class%s+([%w_]+)%s*:?([^{]*)()"):gmatch` benzeri döngü (Lua `string.find` + `init` parametresi, `plain = true` yok). Her eşleşme için:
   - `body_start` = eşleşmeden sonraki ilk `{` konumu, `body_end` = brace sayımıyla eşleşen `}`.
   - `base_text` = yakalanan 2. grup; `trim`, ilk virgülden önce, `<...>` temizle.
   - `class_range` ve `body_byte_range` kaydet.
4. İmleci içeren **en küçük** body aralığını seç. Yoksa `{ class_name = nil, class_kind = nil, implemented = {}, method_ranges = {}, source = "fallback" }`.
5. `class_kind = classify(base_text)`.
6. Metotlar: seçilen class body metni içinde `([%w_<>%[%],%.%s]+)%s+([%w_]+)%s*(%b())` döngüsü; aday adı `class`, `struct`, `interface`, `new`, `return`, `if`, `for`, `while`, `switch`, `using`, `namespace` ise atla. Gövde `{` ile başlıyorsa brace sayımıyla bitiş satırını bul; yoksa (abstract/expression-bodied) bildirim satırını kullan. `(start_line, end_line)` 0-based.
7. `implemented[ad] = true`.
8. Byte offset -> satır çevrimi için `text:sub(1, offset):gsub("\n", "")` sayımı kullan.
9. `class_range.end_line` = sınıf body'sinin kapanış satırı (dahil).

`classify(name)`:
- Son segmenti al (`:` ile böl, son parça), `<...>` temizle.
- Eşleme: `MonoBehaviour -> monobehaviour`, `ScriptableObject -> scriptableobject`, `Editor -> editor`; tam adlarda `UnityEngine.MonoBehaviour`, `UnityEditor.Editor`, `UnityEngine.ScriptableObject` de aynı sonucu verir (son segment yeterli, ama yanlış pozitif riski için: `Editor` kısa adı yalnız tam ad `UnityEditor.Editor` değilse de kabul edilir).

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add lua/unitykit/context/fallback.lua tests/context_spec.lua
git commit -m "feat: add regex fallback context resolution"
```

---

### Task 6: Context cache and orchestration

**Files:**
- Create: `lua/unitykit/context/cache.lua`
- Create: `lua/unitykit/context/init.lua`
- Test: `tests/cache_spec.lua`

**Interfaces:**
- Consumes: `fallback.resolve` (Task 5), `context.lsp.resolve` (Task 7; bu taskte stub'lanır)
- Produces:
  - `require("unitykit.context.cache").get(bufnr) -> Context|nil` (yalnız taze kayıt)
  - `require("unitykit.context.cache").set(bufnr, ctx) -> boolean`
  - `require("unitykit.context.cache").set_pending(bufnr, ctx) -> boolean`
  - `require("unitykit.context.cache").invalidate(bufnr: integer|nil)`
  - `require("unitykit.context.cache").pending(bufnr) -> boolean`
  - `require("unitykit.context").resolve(bufnr: integer, cfg: Config) -> Context`
  - `require("unitykit.context").invalidate(bufnr: integer|nil)`
  - `require("unitykit.context").is_in_class_body(ctx: Context, row: integer) -> boolean`

- [x] **Step 1: Write failing `tests/cache_spec.lua`**

```lua
local cache = require("unitykit.context.cache")

local buf = h.new_buf({ "public class A : MonoBehaviour", "{", "}" }, "cs")
local ctx = { class_name = "A", class_kind = "monobehaviour", class_range = { start_line = 0, end_line = 2 }, method_ranges = {}, implemented = {}, source = "fallback" }

h.eq(cache.get(buf), nil, "bos cache nil")
h.check(cache.set(buf, ctx), "set true")
h.eq(cache.get(buf).class_name, "A", "cache hit")

vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "public class A : MonoBehaviour", "{", "  void Start() {}", "}" })
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
    done({ class_name = "A", class_kind = "scriptableobject", class_range = { start_line = 0, end_line = 3 }, method_ranges = {}, implemented = {}, source = "lsp" })
  end,
}
package.loaded["unitykit.context"] = nil
local context = require("unitykit.context")

h.eq(context.resolve(buf, require("unitykit.config").setup()).source, "fallback", "ilk cagri aninda fallback")
h.eq(lsp_calls, 1, "lsp bir kez tetiklenir")
h.eq(context.resolve(buf, require("unitykit.config").setup()).source, "lsp", "lsp sonucu cache'e yazilir")
h.eq(lsp_calls, 1, "pending iken tekrar istek yok")

-- is_in_class_body
local c = { class_range = { start_line = 2, end_line = 10 }, method_ranges = { { start_line = 5, end_line = 7 } } }
h.check(context.is_in_class_body(c, 2), "sinif satiri govde sayilir")
h.check(context.is_in_class_body(c, 4), "metot disi govde")
h.check(not context.is_in_class_body(c, 5), "metot baslangici disarida")
h.check(not context.is_in_class_body(c, 6), "metot icinde degil")
h.check(not context.is_in_class_body(c, 11), "sinif disi")
h.check(not context.is_in_class_body({ class_range = nil }, 1), "sinif yoksa false")

-- change tick invalidates lsp result too
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "public class A : MonoBehaviour", "{", "}", "// x" })
h.eq(context.resolve(buf, require("unitykit.config").setup()).source, "fallback", "degisiklikten sonra yine fallback")
```

- [x] **Step 2: Run, verify fail.**

- [x] **Step 3: Implement `lua/unitykit/context/cache.lua`**

- `M.entries[bufnr] = { tick = nvim_buf_get_changedtick(bufnr), ctx = ctx, pending = true|false }`
- `get`: kayıt varsa ve `tick == changedtick` ise `ctx` (pending ise `ctx` yine döner — fallback context).
- `set`: tick güncelle, `pending = false`.
- `pending`: kayıt varsa ve tick taze ise `pending` alanı.
- `invalidate(nil)`: tümü; aksi halde tek kayıt.
- `BufWipeout`/`BufDelete` autocmd bir kez (`once` değil, `group` + `clear` korumalı) ile `invalidate(bufnr)`.

- [x] **Step 4: Implement `lua/unitykit/context/init.lua`**

```lua
function M.resolve(bufnr, cfg)
  local cached = cache.get(bufnr)
  if cached then
    if not cache.pending(bufnr) then return cached end
    -- pending: fallback sonucu elde varsa onu dondur
    return cached
  end
  local ctx = fallback.resolve(bufnr)
  cache.set_pending(bufnr, ctx)
  local lsp = require("unitykit.context.lsp")
  local finished = false
  lsp.resolve(bufnr, cfg, function(lsp_ctx)
    if finished then return end
    finished = true
    if lsp_ctx and lsp_ctx.class_kind then cache.set(bufnr, lsp_ctx) end
  end)
  return ctx
end
```

- `cache.set_pending(bufnr, ctx)`: tick + ctx + `pending = true`; `get` bu kaydı döndürür.
- `is_in_class_body(ctx, row)`: `ctx.class_range` ve `row >= start_line` ve `row <= end_line`; `method_ranges` içinde `row >= start_line and row <= end_line` olan varsa `false`.
- `invalidate(bufnr)` -> `cache.invalidate`.

- [x] **Step 5: Run tests, verify pass.**

- [x] **Step 6: Commit**

```bash
git add lua/unitykit/context/init.lua lua/unitykit/context/cache.lua tests/cache_spec.lua
git commit -m "feat: add context cache and LSP-first orchestration"
```

---

### Task 7: LSP inheritance resolution

**Files:**
- Create: `lua/unitykit/context/lsp.lua`
- Test: `tests/context_lsp_spec.lua`

**Interfaces:**
- Consumes: `fallback.classify` (Task 5), `Config.timeout_ms` (Task 1)
- Produces:
  - `require("unitykit.context.lsp").parse_hover_class(markdown: string|nil) -> string|nil` — `"```csharp\nclass UnityEngine.MonoBehaviour\n```"` -> `"UnityEngine.MonoBehaviour"`
  - `require("unitykit.context.lsp").parse_base_names(class_line: string) -> string[]`
  - `require("unitykit.context.lsp").strip_generics(name: string) -> string`
  - `require("unitykit.context.lsp").normalize_method_name(name: string, detail: string|nil) -> string`
  - `require("unitykit.context.lsp").qualify(kind: string) -> string` (test yardımcısı değil; `classify` ile aynı eşleme)
  - `require("unitykit.context.lsp").resolve(bufnr: integer, cfg: Config, done: fun(ctx: Context|nil)) -> nil` — asenkron; her koşulda `done` tam bir kez çağrılır, `timeout_ms` sonunda `nil` ile

- [ ] **Step 1: Write failing `tests/context_lsp_spec.lua`**

```lua
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
```

`h.eq` tablo karşılaştırması `vim.deep_equal` kullanır.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement pure helpers**

- `strip_generics`: `<` öncesini al, `trim`.
- `parse_base_names(line)`: `:` sonrasını al; `{}`/`;` kes; virgülle böl; her parçayı `strip_generics` + `trim`; boşları at. `(` içerenleri (constructor constraint) at.
- `normalize_method_name(name, detail)`: `name` içindeki ilk `(` öncesi; boşsa `detail` üzerinde aynı işlem; `trim`; `strip_generics` uygulama (metot adı generic olmaz).
- `parse_hover_class(md)`: `class%s+([%w_%.]+)` deseni; ilk yakalama. `struct`/`interface`/`enum` -> nil (desen zaten `class` arar, ama `class` içeren düz metin yanlış pozitif üretmesin diye yalnız ```csharp bloğunun ilk satırına bak).
- `KIND_BY_QUALIFIED` = `{ ["UnityEngine.MonoBehaviour"] = "monobehaviour", ["UnityEngine.ScriptableObject"] = "scriptableobject", ["UnityEditor.Editor"] = "editor" }`; `qualify(kind)` ters eşleme.

- [ ] **Step 4: Implement `resolve(bufnr, cfg, done)`**

Akış (her adım `pcall` ve iptal bayrağıyla korunur):

1. `client = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentSymbol" })[1]`; yoksa `done(nil)` döndür (senkron, `vim.schedule` kullanma — test bunu bekliyor).
2. `deadline = uv.now() + cfg.timeout_ms`; `finish(ctx)` yardımcısı `once` semantiği uygular, `done(ctx)` çağırır.
3. `client:request("textDocument/documentSymbol", { textDocument = ... }, handler, bufnr)`:
   - handler içinde imleci içeren `kind == 5` (Class) en içteki sembolü bul -> `class_sym`.
   - `class_sym` yoksa `finish(nil)`.
   - `class_line = nvim_buf_get_lines(bufnr, class_sym.range.start.line, class_sym.range.start.line + 1, false)[1]`
   - `bases = parse_base_names(class_line)`; boşsa sınıf tanımının devam satırlarını (`start.line + 1 .. start.line + 3`) birleştirip yeniden dene (çok satırlı base list).
   - `implemented` ve `method_ranges`: `class_sym.children` içinde `kind == 6` olanlar; `normalize_method_name(child.name, child.detail)`; `method_ranges = child.range` satırları.
   - `class_kind` çözümü: `resolve_kind(bases, class_sym, bufnr, client, 0, deadline)`.
4. `resolve_kind(bases, ...)`: her base için
   - `plain = strip_generics(base)`; `fallback.classify(plain)` sonuç verirse dön.
   - Base identifier'ın buffer'daki konumunu `class_decl_line` içinde `find(plain, 1, true)` ile bul; `hover` iste.
   - `hover` -> `parse_hover_class` -> `fallback.classify(qualified)` sonuç verirse dön.
   - `qualified` proje sınıfıysa (`class Deneme`) `workspace/symbol` ile `query = plain` ara; `kind == 5` ve `name == plain` olan ilk sembolü al; dosyasını `vim.fn.readfile` ile oku (buffer yüklüyse `nvim_buf_get_lines`), sınıf satırından `parse_base_names` çıkar, `depth + 1` ile tekrarla.
   - `depth >= 8` veya süre doldu -> `nil`.
5. `finish(ctx)` — `ctx` alanları: `class_name`, `class_kind`, `class_range`, `method_ranges`, `implemented`, `source = "lsp"`.
6. Zaman aşımı: `uv.new_timer()` ile `cfg.timeout_ms` sonunda `finish(nil)`; timer `stop` + `close`.

Not: `workspace/symbol` desteklenmiyorsa (`client.server_capabilities.workspaceSymbolProvider == false`) yalnız hover ile sınırlı kal, `nil` dön.

- [ ] **Step 5: Run tests, verify pass.**

- [ ] **Step 6: Commit**

```bash
git add lua/unitykit/context/lsp.lua tests/context_lsp_spec.lua
git commit -m "feat: resolve Unity class kind via LSP hover and symbol chain"
```

---

### Task 8: nvim-cmp source

**Files:**
- Create: `lua/unitykit/completion/cmp.lua`
- Test: `tests/source_spec.lua`

**Interfaces:**
- Consumes: `config.setup` (Task 1), `project.root` (Task 2), `messages.get` (Task 3), `item.to_cmp_item` (Task 4), `context.resolve` + `is_in_class_body` (Task 6)
- Produces:
  - `require("unitykit.completion.cmp").items(bufnr: integer, cfg: Config) -> table[]` (test edilebilir çekirdek)
  - `require("unitykit.completion.cmp").register(cfg: Config)` — `pcall(require, "cmp").register_source("unitykit", source)`; cmp yoksa sessiz döner
  - `require("unitykit.completion.cmp").source` — cmp source tablosu

- [ ] **Step 1: Write failing `tests/source_spec.lua`**

```lua
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
}, 0, -1)
vim.api.nvim_win_set_cursor(0, { 3, 4 })         -- 0-based 2
local so = cmp_source.items(buf, cfg)
local so_names = {}
for _, it in ipairs(so) do so_names[it.word] = true end
h.check(so_names.Reset, "scriptableobject Reset")
h.check(not so_names.Update, "scriptableobject Update yok")

-- register without cmp must not error
local ok, err = pcall(cmp_source.register, cfg)
h.check(ok, "cmp yokken register hata vermez: " .. tostring(err))
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement `items(bufnr, cfg)`**

Guard sırası:

1. `vim.bo[bufnr].filetype` `cfg.filetypes` içinde değilse `{}`.
2. `vim.bo[bufnr].buftype ~= ""` veya `not vim.bo[bufnr].modifiable` -> `{}`.
3. `project.root(bufnr) == nil` -> `{}`.
4. `ctx = context.resolve(bufnr, cfg)`; `ctx.class_kind == nil` -> `{}`.
5. `row = vim.api.nvim_win_get_cursor(0)[1] - 1`; `not context.is_in_class_body(ctx, row)` -> `{}`.
6. `messages.get(ctx.class_kind)` üzerinden dön; `cfg.hide_implemented and ctx.implemented[msg.name]` olanları atla.
7. `item.to_cmp_item(msg, cfg, ctx)`.

`get_trigger_characters` -> `{}`; `keyword_pattern` -> `[[\%([A-Za-z_][A-Za-z0-9_]*\)\?]]`; `priority` -> `cfg.priority and 1000 or 500`.

`complete(params, callback)`:

```lua
local bufnr = vim.api.nvim_get_current_buf()
callback({ items = M.items(bufnr, require("unitykit.config").get()), isIncomplete = false })
```

`is_available` -> buffer'da imleçten önce harf veya `_` var mı (`vim.regex` kullanmadan `line:sub(1, col):match("[%w_]$") ~= nil`).

- [ ] **Step 4: Run tests, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add lua/unitykit/completion/cmp.lua tests/source_spec.lua
git commit -m "feat: add nvim-cmp source"
```

---

### Task 9: setup, health, docs

**Files:**
- Create: `lua/unitykit/init.lua`
- Create: `lua/unitykit/health.lua`
- Create: `doc/unitykit.txt`
- Modify: `README.md` (durum satırı + kullanım)
- Test: `tests/setup_spec.lua`

**Interfaces:**
- Consumes: tüm önceki modüller
- Produces:
  - `require("unitykit").setup(opts: table|nil) -> Config` — config'i uygular, source'u bir kez kaydeder
  - `require("unitykit.health").check()` — `:checkhealth unitykit` tarafından çağrılır

- [ ] **Step 1: Write failing `tests/setup_spec.lua`**

```lua
local registered = 0
local fake_cmp = { register_source = function(name) registered = registered + 1; assert(name == "unitykit") end }
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
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement `lua/unitykit/init.lua`**

```lua
local M = {}
local registered = false

function M.setup(opts)
  local cfg = require("unitykit.config").setup(opts)
  if not registered then
    require("unitykit.completion.cmp").register(cfg)
    registered = true
  end
  return cfg
end

return M
```

- [ ] **Step 4: Implement `lua/unitykit/health.lua`**

`check()` içinde `vim.health.start("unitykit")`, ardından:

- `vim.health.ok("Neovim " .. version)` veya `vim.health.error` (< 0.10).
- `pcall(require, "cmp")` -> ok/warn.
- `package.loaded["unitykit.completion.cmp"]` kayıtlı mı.
- Aktif buffer: `project.root(bufnr)`, `vim.lsp.get_clients({ bufnr = bufnr })` adları, `context.resolve` kaynağı ve `class_kind`.

- [ ] **Step 5: Write `doc/unitykit.txt`**

`:help unitykit` başlığı, `unitykit.setup()` seçenekleri, mesaj türleri, gereksinimler, `:checkhealth unitykit`. Vim help formatı (`*unitykit.txt*`, `*unitykit.setup()*` etiketleri).

- [ ] **Step 6: Update `README.md`**

"Düzenli durum" satırını `Faz 1 tamamlandı` yap; `setup` örneği ve `:checkhealth` satırı ekle; `blink.cmp` kullanıcıları için uyarı (Faz 2).

- [ ] **Step 7: Run full suite**

Run: `tests/run.sh`
Expected: tüm spec'ler `FAIL` içermez, exit 0.

- [ ] **Step 8: Commit**

```bash
git add lua/unitykit/init.lua lua/unitykit/health.lua doc/unitykit.txt README.md tests/setup_spec.lua
git commit -m "feat: add setup, health check and documentation"
```

---

### Task 10: Real Unity project verification

**Files:**
- Modify: `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md` (yalnız doğrulama notu)
- No production code changes unless a bug is found.

**Interfaces:**
- Consumes: tüm modüller
- Produces: doğrulama notu

- [ ] **Step 1: Install into the local neovim config (temporary)**

`~/.config/nvim/lua/plugins/unitykit.lua`:

```lua
return {
  dir = "~/Git/unitykit.nvim",
  dependencies = { "hrsh7th/nvim-cmp" },
  opts = {},
}
```

- [ ] **Step 2: Manual checks in `~/Documents/unity_projects/My project/Assets/Scripts/Deneme.cs`**

- `Sta` -> `Start` önerisi; seç -> blok gövde; `:w` sonrası derleme hatası yok.
- `OnCol` -> `OnCollisionEnter/Stay/Exit` doğru parametrelerle.
- Mevcut `Start` tekrar önerilmez.
- `Update` gövdesi içinde öneri yok.
- Yeni `class Data : ScriptableObject` dosyasında `Update` çıkmaz, `Reset` çıkar.
- Roslyn kapat (`:LspStop`) -> doğrudan `: MonoBehaviour` için çalışır, dolaylı kalıtım çalışmaz.
- `:checkhealth unitykit` durumu doğru gösterir.

- [ ] **Step 3: Record results**

Spec'in sonuna `## 14. Doğrulama Notu` bölümü ekle: tarih, Neovim sürümü, LSP adı, test edilen maddeler, bulunan sapmalar.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-10-27-unitykit-completion-design.md
git commit -m "docs: record phase 1 manual verification"
```

---

## Self-Review

**Spec coverage:** Problem/amaç §2 -> Task 8, 10. Mimari §4 -> Task 6, 7, 8. Bağlam §5 -> Task 5, 6, 7. Mesaj modeli §6 -> Task 3, 4. Completion davranışı §7 -> Task 8. Ayarlar §8 -> Task 1. Proje tespiti §9 -> Task 2. Health §10 -> Task 9. Test §11 -> her task. Kabul kriterleri §13 -> Task 10. Riskler §12 -> Task 7 (timeout/desen), Task 3 (modifiers), Task 2 (kök tespiti).

**Step scan:** Her adım tek eylem + doğrulanabilir sonuç; kod blokları yalnız imza/örnek düzeyinde.

**Type consistency:** `class_range`/`method_ranges` tüm tasklerde `{start_line, end_line}` 0-based; `Context.source` değerleri `"lsp"|"fallback"`; `item.render`/`to_cmp_item` imzaları Task 4 ve Task 8'de aynı; `config.setup` dönüşü her yerde `Config`.

**Review Focus:** Beş maddenin testleri: metot gövdesi (Task 8 Step 1), iç içe/çoklu sınıf (Task 5 Step 1), çok satırlı bildirim (Task 5 Step 1), attribute'lı metot (Task 5 Step 1), generic + çoklu base (Task 5 Step 1).
