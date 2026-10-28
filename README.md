# unitykit.nvim

Unity geliştirme araç seti — Neovim için.

Faz 1 hedefi: Unity message completion. `Awake`, `Start`, `Update`,
`OnCollisionEnter` gibi Unity'nin çağırdığı sihirli metotları doğru imza ve
gövde ile tamamlar. C# LSP bu metotları bilmez; bu eklenti boşluğu kapatır.

> Durum: Faz 1 tamamlandı (MonoBehaviour, ScriptableObject, Editor mesaj
> setleri; nvim-cmp source; `:checkhealth unitykit`).

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
  config = function()
    require("unitykit").setup()
  end,
}
```

Source'u cmp'ye kaydedin ve önceliğini **cmp tarafında** verin:

```lua
require("cmp").setup({
  sources = {
    { name = "unitykit", priority = 1000 },
    { name = "nvim_lsp" },
    { name = "buffer" },
  },
})
```

cmp, source tablosundaki bir `priority` alanını okumaz; öncelik yalnız
`sources` listesinde ayarlanır. `unitykit.setup()` source'u süreç başına bir
kez kaydeder, tekrar çağrıları yalnız ayarları günceller.

## Ayarlar

```lua
require("unitykit").setup({
  filetypes = { "cs" },
  body = "block",            -- "block" | "line"
  access = "none",           -- "none" | "private" | "public" | "protected"
  hide_implemented = true,
  priority = true,           -- sortText öneki; cmp source önceliği değil
  timeout_ms = 1500,
})
```

`setup` birleştirilmiş config tablosunu döndürür. Source kaydı bir kez
başarıyla yapılır; nvim-cmp o anda yüklü değilse sonraki `setup()` çağrısı
kaydı yeniden dener. `require("unitykit").is_registered()` kaydın durumunu
bildirir. Ayrıntılar: `:help unitykit-config`.

## Sağlık kontrolü

```vim
:checkhealth unitykit
```

Neovim sürümü, nvim-cmp, kayıtlı source, aktif buffer'daki Unity kökü ve C# LSP
client'ları raporlanır. Bağlam kaynağı (`lsp` / `fallback`) ile sınıf adı ve
türü yalnız cache'te varsa gösterilir; `:checkhealth` bağlam çözmez ve LSP
isteği göndermez.

## Sınırlar

`blink.cmp` henüz desteklenmiyor; yalnız nvim-cmp source'u var. blink.cmp
adaptörü Faz 2'de planlanıyor.

## Dokümantasyon

- Yardım: `:help unitykit` (kaynak: `doc/unitykit.txt`)
- Tasarım: `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md`

## Lisans

MIT — `LICENSE` dosyasına bakın.
