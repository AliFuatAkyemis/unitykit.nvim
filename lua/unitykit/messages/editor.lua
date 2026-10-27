-- UnityEditor.Editor message signatures and one-line Turkish descriptions.
-- Every editor message is overridden, so `modifiers` is always "public override".
return {
  -- Lifecycle
  {
    name = "Awake",
    modifiers = "public override",
    doc = "Editör örneği oluşturulduğunda çağrılır.",
  },
  {
    name = "OnEnable",
    modifiers = "public override",
    doc = "Editör örneği etkinleştirildiğinde çağrılır.",
  },
  {
    name = "OnDisable",
    modifiers = "public override",
    doc = "Editör örneği devre dışı bırakıldığında çağrılır.",
  },
  {
    name = "OnDestroy",
    modifiers = "public override",
    doc = "Editör örneği yok edilirken çağrılır.",
  },
  {
    name = "OnValidate",
    modifiers = "public override",
    doc = "Inspector'da değer değiştiğinde veya betik yeniden yüklendiğinde çağrılır.",
  },
  {
    name = "Reset",
    modifiers = "public override",
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
    modifiers = "public override",
    doc = "Sahne görünümünde etkileşim çizimi için çağrılır.",
  },
  {
    name = "OnHeaderGUI",
    modifiers = "public override",
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
