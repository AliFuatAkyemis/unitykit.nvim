# unitykit.nvim

Unity geliştirme araç seti — Neovim için.

Faz 1 hedefi: Unity message completion. `Awake`, `Start`, `Update`,
`OnCollisionEnter` gibi Unity'nin çağırdığı sihirli metotları doğru imza ve
gövde ile tamamlar. C# LSP bu metotları bilmez; bu eklenti boşluğu kapatır.

> Durum: tasarım tamamlandı, uygulama planı hazırlanıyor. Kod henüz yok.

## Gereksinimler

- Neovim >= 0.10
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- Unity projesi (`Assets/` + `ProjectSettings/ProjectVersion.txt`)

Opsiyonel: C# LSP (Roslyn önerilir). LSP yoksa eklenti doğrudan `: MonoBehaviour`
yazan sınıflarda çalışır, dolaylı kalıtımı çözmez.

## Kurulum

```lua
{
  "alifuat/unitykit.nvim",
  dependencies = { "hrsh7th/nvim-cmp" },
  opts = {},
}
```

## Ayarlar

```lua
require("unitykit").setup({
  filetypes = { "cs" },
  body = "block",            -- "block" | "line"
  access = "none",           -- "none" | "private" | "public" | "protected"
  hide_implemented = true,
  priority = true,
  timeout_ms = 1500,
})
```

## Dokümantasyon

- Tasarım: `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md`

## Lisans

Henüz belirlenmedi.
