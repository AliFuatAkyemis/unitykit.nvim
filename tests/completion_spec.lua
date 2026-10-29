local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

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
h.eq(cmp_item.preselect, true, "ilk item secili gelsin")
h.check(cmp_item.documentation.value:find("Start", 1, true) ~= nil, "dokuman mesaj adini icerir")
h.check(cmp_item.documentation.value:find("void Start()", 1, true) ~= nil, "dokuman imzayi icerir")

local no_priority = item.to_cmp_item(start, require("unitykit.config").setup({ priority = false }))
h.eq(no_priority.sortText, nil, "priority false -> sortText yok")

h.eq(item.render({ name = "X", doc = "" }, require("unitykit.config").setup({ access = "protected" })),
  "protected void X()\n{\n    $0\n}", "protected erisim")

h.finish()
