local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")

local messages = require("unitykit.messages")

h.eq(messages.kinds, { "monobehaviour", "scriptableobject", "editor" }, "tur sirasi")

local mono = messages.get("monobehaviour")
local names = {}
for _, m in ipairs(mono) do
  names[m.name] = true
end

for _, expected in ipairs({
  "Awake",
  "OnEnable",
  "Start",
  "FixedUpdate",
  "Update",
  "LateUpdate",
  "OnDisable",
  "OnDestroy",
  "OnValidate",
  "Reset",
  "OnCollisionEnter",
  "OnCollisionStay",
  "OnCollisionExit",
  "OnTriggerEnter",
  "OnTriggerStay",
  "OnTriggerExit",
  "OnControllerColliderHit",
  "OnParticleCollision",
  "OnMouseEnter",
  "OnMouseOver",
  "OnMouseExit",
  "OnMouseDown",
  "OnMouseUp",
  "OnMouseUpAsButton",
  "OnMouseDrag",
  "OnGUI",
  "OnDrawGizmos",
  "OnDrawGizmosSelected",
  "OnBecameVisible",
  "OnBecameInvisible",
  "OnApplicationFocus",
  "OnApplicationPause",
  "OnApplicationQuit",
  "OnTransformChildrenChanged",
  "OnTransformParentChanged",
  "OnAudioFilterRead",
}) do
  h.check(names[expected], "mono icinde " .. expected)
end

h.eq(
  messages.get_by_name("monobehaviour", "OnCollisionEnter").params,
  "Collision collision",
  "collision imzasi"
)
h.eq(
  messages.get_by_name("monobehaviour", "OnTriggerEnter").params,
  "Collider other",
  "trigger imzasi"
)
h.eq(messages.get_by_name("monobehaviour", "OnMouseDown").params, nil, "parametresiz mesaj")
h.eq(
  messages.get_by_name("monobehaviour", "OnApplicationFocus").params,
  "bool hasFocus",
  "bool parametre"
)

local so = {}
for _, m in ipairs(messages.get("scriptableobject")) do
  so[m.name] = true
end
h.check(so.Reset, "scriptableobject Reset var")
h.check(not so.Update, "scriptableobject Update yok")

local editor = messages.get("editor")
h.check(#editor > 0, "editor listesi bos degil")

-- Three groups, verified against UnityCsReference:
--  - genuine overrides (public virtual) -> "public override"
--  - OnHeaderGUI (protected virtual) -> "protected override"
--  - lifecycle + OnSceneGUI (native dispatch) -> no modifiers
local OVERRIDES = {
  "OnInspectorGUI",
  "HasPreviewGUI",
  "OnPreviewGUI",
  "OnInteractivePreviewGUI",
  "RequiresConstantRepaint",
}
local PROTECTED = { "OnHeaderGUI" }
local NATIVE = {
  "Awake",
  "OnEnable",
  "OnDisable",
  "OnDestroy",
  "OnValidate",
  "Reset",
  "OnSceneGUI",
}
for _, name in ipairs(OVERRIDES) do
  h.eq(messages.get_by_name("editor", name).modifiers, "public override", "override: " .. name)
end
for _, name in ipairs(PROTECTED) do
  h.eq(messages.get_by_name("editor", name).modifiers, "protected override", "protected: " .. name)
end
for _, name in ipairs(NATIVE) do
  h.eq(messages.get_by_name("editor", name).modifiers, nil, "native: " .. name)
end
h.eq(messages.get_by_name("editor", "HasPreviewGUI").returns, "bool", "HasPreviewGUI bool doner")
h.eq(
  messages.get_by_name("editor", "RequiresConstantRepaint").returns,
  "bool",
  "RequiresConstantRepaint bool doner"
)
h.eq(
  messages.get_by_name("editor", "OnPreviewGUI").params,
  "Rect r, GUIStyle background",
  "OnPreviewGUI imzasi"
)

h.eq(messages.get("nope"), {}, "bilinmeyen tur bos liste")
h.eq(messages.get_by_name("nope", "Start"), nil, "bilinmeyen tur nil")

local seen = {}
for _, m in ipairs(mono) do
  h.check(not seen[m.name], "tekrar yok: " .. m.name)
  seen[m.name] = true
end
for kind, list in pairs({
  monobehaviour = mono,
  scriptableobject = messages.get("scriptableobject"),
  editor = editor,
}) do
  for _, m in ipairs(list) do
    h.check(type(m.doc) == "string" and #m.doc > 0, "doc dolu: " .. kind .. "." .. m.name)
  end
end

h.finish()
