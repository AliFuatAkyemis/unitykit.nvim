# unitykit.nvim

Unity geliştirme araç seti — Neovim için.

Unity'nin yansıma (reflection) ile çağırdığı `Awake`, `Start`, `Update`,
`OnCollisionEnter` gibi metotları doğru imza ve gövdeyle tamamlar. C# LSP'leri
bu "sihirli" metotları bilmez; unitykit bu boşluğu kapatır.

MonoBehaviour, ScriptableObject ve `UnityEditor.Editor` mesaj setlerini kapsar;
nvim-cmp source'u olarak çalışır ve `:checkhealth unitykit` ile kendini denetler.

## İçindekiler

- [Ne yapar](#ne-yapar)
- [Gereksinimler](#gereksinimler)
- [Kurulum](#kurulum)
  - [1. Ön koşulları doğrula](#1-ön-koşulları-doğrula)
  - [2. Eklentiyi ekle](#2-eklentiyi-ekle)
  - [3. cmp source'unu kaydet](#3-cmp-sourceunu-kaydet)
  - [4. Unity Editor tarafını hazırla](#4-unity-editor-tarafını-hazırla)
  - [5. Kurulumu doğrula](#5-kurulumu-doğrula)
- [Kullanım](#kullanım)
- [Ayarlar](#ayarlar)
- [Sağlık kontrolü](#sağlık-kontrolü)
- [Sorun giderme](#sorun-giderme)
- [Sınırlar](#sınırlar)
- [Kaldırma](#kaldırma)
- [Dokümantasyon](#dokümantasyon)
- [Lisans](#lisans)

## Ne yapar

- Bir sınıf gövdesinde yazarken Unity mesajlarını önerir: MonoBehaviour (36
  mesaj), ScriptableObject (6) ve Editor (13).
- Seçilen mesajı imzası ve gövdesiyle birlikte ekler:

  ```csharp
  void Start()
  {
      █
  }
  ```

- Gövde tek satır da olabilir: `void Start() { █ }`.
- Zaten yazılmış mesajları listeden gizler (kapatılabilir).
- Sınıf türünü önce C# LSP'sinden, LSP yoksa sınıf bildirimini tarayarak
  bulur; böylece `class Player : BaseEnemy` gibi dolaylı kalıtım da çözülür.
- Hiçbir dosya yazmaz, projeye veya Neovim config'ine iz bırakmaz.

## Gereksinimler

| Gereksinim | Not |
| :-- | :-- |
| **Neovim ≥ 0.10** | `vim.lsp.get_clients`, `vim.health` API'leri kullanılır. |
| **[nvim-cmp](https://github.com/hrsh7th/nvim-cmp)** | Tek zorunlu bağımlılık. |
| **Unity projesi** | Kökte `Assets/` ve `ProjectSettings/ProjectVersion.txt` bulunmalı. |
| **C# LSP** *(opsiyonel)* | Roslyn önerilir. Yoksa eklenti yalnız doğrudan `: MonoBehaviour`, `: ScriptableObject`, `: Editor` yazan sınıflarda çalışır. |

## Kurulum

Eklentiyi hiç kurmamış biri için sırayla izlenecek adımlar aşağıda. Her adım
bir öncekinin üzerine kurulur.

### 1. Ön koşulları doğrula

```bash
nvim --version | head -1   # v0.10 veya üstü olmalı
git --version
```

`nvim-cmp` kurulu değilse önce onu ekleyin (lazy.nvim örneği):

```lua
-- lua/plugins/cmp.lua
return {
  "hrsh7th/nvim-cmp",
  dependencies = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer" },
  config = function()
    require("cmp").setup()
  end,
}
```

### 2. Eklentiyi ekle

`lua/plugins/unitykit.lua` dosyasını oluşturun:

```lua
return {
  "AliFuatAkyemis/unitykit.nvim",
  dependencies = { "hrsh7th/nvim-cmp" },
  config = function()
    require("unitykit").setup()
  end,
}
```

Neovim'i yeniden başlatın; lazy.nvim eklentiyi indirir. `:Lazy` ekranında
`unitykit.nvim` görünmelidir.

> lazy.nvim dışında bir yönetici kullanıyorsanız aynı `dependencies` +
> `require("unitykit").setup()` ikilisini kendi spec formatınıza uyarlayın.

### 3. cmp source'unu kaydet

`require("unitykit").setup()` source'u cmp'ye tanıtır, ancak **öncelik cmp
tarafında** verilir:

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
`sources` listesinde ayarlanır. `unitykit.setup()` source'u süreç başına bir kez
kaydeder, tekrar çağrıları yalnız ayarları günceller.

### 4. Unity Editor tarafını hazırla

unitykit bir Neovim eklentisidir; Unity projesine paket olarak kurulmaz.
Editör tarafında yalnızca **proje dosyalarının üretilmesi** ve (isterseniz)
Unity'nin dosyaları Neovim'de açması gerekir.

1. **Proje dosyalarını üret.** Unity'de
   `Edit ▸ Preferences ▸ External Tools` yolunu açın ve
   *Generate .csproj files for* altında en az **Registry packages** ile
   **Local packages** seçeneklerini işaretleyin. Ardından **Regenerate project
   files** düğmesine basın. Proje kökünde `.sln` ve `.csproj` dosyaları
   oluşur; C# LSP'si bu dosyaları okur (LSP opsiyoneldir, unitykit onsuz da
   çalışır).
2. **IDE paketi (önerilir).** `Window ▸ Package Manager ▸ Unity Registry`
   altından `Visual Studio Editor` veya `JetBrains Rider Editor` paketini
   kurun. Bu paketler yukarıdaki *Regenerate project files* düğmesini ve
   harici editör entegrasyonunu sağlar.
3. **Neovim'i harici editör yap (opsiyonel).** Unity doğrudan Neovim'i
   başlatamaz; küçük bir sarmalayıcı betik gerekir:

   ```bash
   # ~/bin/unity-nvim  (chmod +x ~/bin/unity-nvim)
   #!/usr/bin/env bash
   exec alacritty -e nvim "+call cursor($2, $3)" "$1"
   ```

   `External Tools ▸ External Script Editor ▸ Browse` ile bu betiği seçin.
   Unity dosya adını, satırı ve sütunu argüman olarak geçirir; betikteki
   terminal emülatörünü kendi kullandığınızla değiştirin.

> Neovim'den Unity'ye herhangi bir şey kurulmaz; `Assets/`, `Packages/` veya
> `ProjectSettings/` altında değişiklik oluşmaz. Adım 1 yalnız C# LSP'si için
> gereklidir, unitykit'in kendisi için zorunlu değildir.

### 5. Kurulumu doğrula

Bir C# dosyası açıp (Unity projesi içinde) şunu çalıştırın:

```vim
:checkhealth unitykit
```

Sağlıklı kurulumda görünenler:

```text
- OK Neovim 0.10+ ...
- OK nvim-cmp is installed
- OK Source: unitykit is registered
- OK Unity project root: /path/to/project
- OK C# LSP: roslyn            (LSP varsa)
```

Son olarak bir sınıf gövdesinde `Sta` yazıp tamamlama listesini açın;
`Start()` önerisi gövdesiyle birlikte gelmelidir.

## Kullanım

1. Unity projesi içindeki bir `.cs` dosyasını açın.
2. Sınıf gövdesinde mesaj adının birkaç harfini yazın.
3. nvim-cmp listesinden seçin; imza ve gövde snippet olarak eklenir.

Tamamlama yalnızca şu koşullarda öneri üretir:

- buffer'ın `filetype` değeri `cs` (ayarlanabilir),
- buffer normal bir dosya (`buftype` boş ve `modifiable`),
- dosya bir Unity kökünün altında,
- imleç tanınan bir Unity sınıfının gövdesinde.

Sınıf türü belirlenemezse (ör. `: MonoBehaviour` yazmayan ve LSP'si olmayan
dolaylı kalıtım) öneri gelmez — bu bilinçli bir sınırdır, yanlış öneri
üretmektense susar.

## Ayarlar

Tüm anahtarlar opsiyoneldir.

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

| Anahtar | Varsayılan | Açıklama |
| :-- | :-- | :-- |
| `filetypes` | `{ "cs" }` | Öneri sunulan filetype'lar. |
| `body` | `"block"` | `"block"` çok satırlı gövde, `"line"` tek satır. |
| `access` | `"none"` | Kendi modifier'ı olmayan mesajlara eklenecek erişim belirleyici. |
| `hide_implemented` | `true` | Sınıfta zaten geçen mesaj adlarını listeden çıkarır (büyük/küçük harfe duyarlı). |
| `priority` | `true` | Öğelere `sortText = "0" .. ad` verir; böylece Unity mesajları LSP öğelerinin üstünde sıralanır. |
| `timeout_ms` | `1500` | LSP yanıtı için beklenecek süre. Tamamlama bloklanmaz; regex sonucu hemen döner, geçerli LSP yanıtı sonradan üzerine yazılır. |

`setup` birleştirilmiş config tablosunu döndürür. Geçersiz `body` / `access`
değerleri uyarı verip varsayılana döner. Source kaydı bir kez başarıyla
yapılır; nvim-cmp o anda yüklü değilse sonraki `setup()` çağrısı kaydı yeniden
dener. `require("unitykit").is_registered()` kaydın durumunu bildirir.
Ayrıntılar: `:help unitykit-config`.

## Sağlık kontrolü

```vim
:checkhealth unitykit
```

Neovim sürümü, nvim-cmp, kayıtlı source, aktif buffer'daki Unity kökü ve C# LSP
client'ları raporlanır. Bağlam kaynağı (`lsp` / `fallback`) ile sınıf adı ve
türü yalnız cache'te varsa gösterilir; `:checkhealth` bağlam çözmez ve LSP
isteği göndermez.

## Sorun giderme

| Belirti | Olası neden / çözüm |
| :-- | :-- |
| Öneri hiç gelmiyor | `:checkhealth unitykit` — source kayıtlı mı, dosya Unity kökü altında mı? |
| `Source: unitykit is not registered` | nvim-cmp yüklenmeden `setup()` çağrılmış. `config = function()` içinde `setup()` çağırın ve Neovim'i yeniden başlatın. |
| Öneriler listenin altında kalıyor | cmp `sources` listesine `priority = 1000` ekleyin; `setup({ priority = true })` yalnız `sortText`'i etkiler. |
| Unity kökü bulunamıyor | Proje kökünde `Assets/` ve `ProjectSettings/ProjectVersion.txt` olmalı; dosya bu ağacın dışındaysa çalışmaz. |
| Dolaylı kalıtımda öneri yok | C# LSP kurun (Roslyn) ve `.sln` / `.csproj` dosyalarının üretildiğinden emin olun. |

## Sınırlar

- **`blink.cmp` desteklenmiyor.** Yalnız nvim-cmp source'u vardır; bu yüzden
  blink.cmp kullanan kurulumlar öneri görmez.
- Mesaj listeleri eklentiyle birlikte gelir (statik); Unity sürümüne göre
  otomatik güncellenmez.
- Yalnızca üç sınıf türü tanınır: MonoBehaviour, ScriptableObject ve
  `UnityEditor.Editor`.

## Kaldırma

Eklenti hiçbir dosya, cache dizini veya Unity projesi ayarı yazmaz. Kaldırmak
için yalnızca kendi eklediğiniz satırları geri alın:

1. **Eklenti spec'ini silin** — `lua/plugins/unitykit.lua` dosyasını silin
   (veya spec'i eklediğiniz dosyadan bloğu çıkarın).
2. **cmp source kaydını silin** — `require("cmp").setup({ sources = ... })`
   içinden `{ name = "unitykit", priority = 1000 }` satırını çıkarın.
3. **Varsa `setup()` çağrısını silin** — eklentiyi başka bir yerde
   `require("unitykit").setup({...})` ile yapılandırdıysanız o bloğu kaldırın.
4. **Eklentiyi fiziksel olarak temizleyin** — Neovim'i yeniden başlatıp:

   ```vim
   :Lazy clean
   ```

   Bu komut artık spec'i olmayan eklentileri (unitykit.nvim dahil) siler.
   Elle silmek isterseniz: `rm -rf ~/.local/share/nvim/lazy/unitykit.nvim`.

5. **Doğrulayın** — `:checkhealth unitykit` artık "not found" demeli;
   `:Lazy` listesinde eklenti görünmemeli.

Tempoya dair notlar:

- `lazy-lock.json` kullanıyorsanız `unitykit.nvim` girdisi `:Lazy clean`
  sonrası kendiliğinden düşer; düşmezse dosyadan o satırı silin.
- Unity projesinde temizlenecek bir şey yoktur: `Assets/`, `Packages/` ve
  `ProjectSettings/` altına hiçbir şey yazılmaz. Adım 4'te anlatılan `.sln` /
  `.csproj` dosyaları Unity'ye aittir ve LSP için gereklidir; unitykit'i
  kaldırmak bunları silmeyi gerektirmez.
- Tüm eklenti durumu bellekte tutulur (buffer cache, cmp kaydı); Neovim
  kapandığında kendiliğinden yok olur.

## Dokümantasyon

- Yardım: `:help unitykit` (kaynak: `doc/unitykit.txt`)
- Tasarım: `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md`

## Lisans

MIT — `LICENSE` dosyasına bakın.
