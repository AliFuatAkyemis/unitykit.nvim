-- UnityEditor.Editor message signatures and one-line Turkish descriptions.
-- Only genuine overrides carry `modifiers`; lifecycle messages and OnSceneGUI
-- are dispatched natively and take no access modifier.
return {
  -- Lifecycle (native message dispatch; no modifiers)
  {
    name = "Awake",
    doc = "Editör örneği oluşturulduğunda çağrılır.",
  },
  {
    name = "OnEnable",
    doc = "Editör örneği etkinleştirildiğinde çağrılır.",
  },
  {
    name = "OnDisable",
    doc = "Editör örneği devre dışı bırakıldığında çağrılır.",
  },
  {
    name = "OnDestroy",
    doc = "Editör örneği yok edilirken çağrılır.",
  },
  {
    name = "OnValidate",
    doc = "Inspector'da değer değiştiğinde veya betik yeniden yüklendiğinde çağrılır.",
  },
  {
    name = "Reset",
    doc = "Editör hedefi Inspector'da sıfırlandığında çağrılır.",
  },

  -- Drawing
  {
    name = "OnInspectorGUI",
    modifiers = "public override",
    doc = "Inspector paneli çizilirken çağrılır.",
  },
  {
    name = "OnSceneGUI",
    doc = "Sahne görünümünde etkileşim çizimi için çağrılır.",
  },
  {
    name = "OnHeaderGUI",
    modifiers = "protected override",
    doc = "Inspector başlığı çizilirken çağrılır.",
  },

  -- Preview
  {
    name = "HasPreviewGUI",
    returns = "bool",
    modifiers = "public override",
    doc = "Inspector önizlemesi olup olmadığını bildirmek için çağrılır.",
  },
  {
    name = "OnPreviewGUI",
    params = "Rect r, GUIStyle background",
    modifiers = "public override",
    doc = "Inspector önizleme alanı çizilirken çağrılır.",
  },
  {
    name = "OnInteractivePreviewGUI",
    params = "Rect r, GUIStyle background",
    modifiers = "public override",
    doc = "Etkileşimli önizleme alanı çizilirken çağrılır.",
  },
  {
    name = "RequiresConstantRepaint",
    returns = "bool",
    modifiers = "public override",
    doc = "Önizlemenin sürekli yeniden çizim gerektirip gerektirmediğini bildirmek için çağrılır.",
  },
}
