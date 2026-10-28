-- ScriptableObject message signatures and one-line Turkish descriptions.
return {
  { name = "Awake", doc = "ScriptableObject örneği yüklendiğinde bir kez çağrılır." },
  { name = "OnEnable", doc = "Nesne etkinleştirildiğinde çağrılır." },
  { name = "OnDisable", doc = "Nesne devre dışı bırakıldığında çağrılır." },
  { name = "OnDestroy", doc = "Nesne yok edilirken çağrılır." },
  {
    name = "OnValidate",
    doc = "Inspector'da değer değiştiğinde veya betik yeniden yüklendiğinde çağrılır.",
  },
  { name = "Reset", doc = "Nesne Inspector'da sıfırlandığında çağrılır." },
}
