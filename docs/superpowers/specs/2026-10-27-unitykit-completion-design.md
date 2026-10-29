# unitykit.nvim — Faz 1: Unity Message Completion

Tarih: 2026-10-27
Durum: Onaylandı (uygulama planı bekliyor)
Kapsam: Faz 1

## 1. Problem

Neovim'de C# LSP (Roslyn) Unity API tiplerini ve üyelerini tamamlar, fakat
Unity'nin çağırdığı sihirli metotları (`Awake`, `Start`, `Update`,
`OnCollisionEnter`, ...) **tamamlamaz**. Bu metotlar `MonoBehaviour` üyesi
değildir; Unity bunları yansıma ile çağırır. Sonuç: her yeni script'te imzalar
elle yazılır, imza hataları (`OnCollisionEnter(Collider)` gibi) derleme veya
çalışma zamanında ortaya çıkar.

Microsoft'un VS Code Unity Extension'ı bu boşluğu kendi code model'i ile
doldurur, ancak motoru VS Code API'lerine bağlıdır ve Neovim'e taşınamaz
(denendi: `roslyn_ls --extension=UnityCodeAnalysis.dll` ile `Start` gelmedi).

## 2. Amaç

Saf Neovim/Neovide içinde, sınıfın türüne uygun Unity mesajlarını doğru imza
ve gövde ile öneren küçük, bağımsız bir eklenti.

Başarı ölçütü:

- `Sta` yazıp tamamlayınca `void Start()` + blok gövde çıkar.
- `OnCol` yazınca `OnCollisionEnter`, `OnCollisionStay`, `OnCollisionExit`
  doğru parametre tipleriyle çıkar.
- `ScriptableObject` türevinde MonoBehaviour mesajları **çıkmaz**.
- Zaten yazılmış mesajlar önerilmez.
- Metot gövdesi içinde öneri çıkmaz.
- C# LSP yokken de doğrudan `: MonoBehaviour` yazan sınıfta çalışır.
- LSP yavaş/hatalı olsa bile completion bloklanmaz.

## 3. Kapsam Dışı (Faz 1)

- Debugger / DAP
- Analyzer, uyarılar, code action, refactoring
- `.asmdef`, `.shader`, `.uss`, `.uxml` sözdizimi
- Unity Editor entegrasyonu, code lens, csproj üretimi
- `blink.cmp` adaptörü
- Unity kurulumundan mesaj listesi okuma
- `EditorWindow`, `ScriptableWizard`, `StateMachineBehaviour`, `NetworkBehaviour`
  mesaj setleri (sonraki faz)
- Unity API dokümantasyon tarayıcısı

## 4. Mimari

LSP-first hibrit. Üç katman:

```
completion/cmp.lua  ->  context/init.lua  ->  messages/init.lua
                              |
                    context/lsp.lua  |  context/fallback.lua
                              |
                       context/cache.lua
```

### 4.1 Modüller

| Modül | Sorumluluk |
|---|---|
| `unitykit.init` | `setup()`, varsayılanları birleştir, cmp source kaydet |
| `unitykit.config` | Varsayılan ayarlar, doğrulama |
| `unitykit.project` | Unity kökü tespiti (`Assets/` + `ProjectSettings/ProjectVersion.txt`), cache |
| `unitykit.messages` | Tür -> mesaj listesi sorgusu, isim indeksi |
| `unitykit.messages.monobehaviour` | MonoBehaviour mesaj tablosu |
| `unitykit.messages.scriptableobject` | ScriptableObject mesaj tablosu |
| `unitykit.messages.editor` | Editor mesaj tablosu |
| `unitykit.context` | Bağlam çözümü orkestrasyonu |
| `unitykit.context.lsp` | `documentSymbol`, `hover`, `definition` istekleri |
| `unitykit.context.fallback` | Regex tabanlı sınıf/tür/metot tespiti |
| `unitykit.context.cache` | Buffer bazlı sonuç cache'i |
| `unitykit.completion.cmp` | `nvim-cmp` source |
| `unitykit.completion.item` | Mesaj -> cmp item (snippet + doküman) |
| `unitykit.health` | `:checkhealth unitykit` |

### 4.2 Akış

1. Kullanıcı insert modunda yazar; `nvim-cmp` `complete()` çağırır.
2. `completion.cmp` guard'ları çalıştırır (filetype, Unity projesi).
3. `context.resolve(bufnr)` çağrılır:
   - cache hit -> hazır bağlam
   - cache miss -> fallback bağlam **hemen** döner, LSP çözümü arka planda
     başlar ve cache'i günceller
4. Bağlamdan mesaj listesi seçilir.
5. `hide_implemented` ise mevcut metotlar filtrelenir.
6. `completion.item` her mesajı snippet item'a çevirir.
7. cmp filtrelemeyi yapar, kullanıcı seçince `vim.snippet.expand` çalışır.

## 5. Bağlam Çözümü

Bağlam nesnesi:

```lua
---@class unitykit.Context
---@field class_name string|nil        -- en içteki sınıf adı
---@field class_kind "monobehaviour"|"scriptableobject"|"editor"|nil
---@field class_start integer|nil     -- 0-based satır
---@field class_end integer|nil       -- 0-based satır (dahil)
---@field implemented table<string, true>  -- normalize edilmiş metot adları
---@field source "lsp"|"fallback"
```

### 5.1 Sınıf tespiti (LSP)

`textDocument/documentSymbol` bir kez çağrılır. İmleç konumunu içeren, `kind`
değeri `Class` (5) olan **en içteki** sembol seçilir (iç içe sınıflar için
`range` karşılaştırması).

### 5.2 Tür tespiti (LSP)

1. Sınıf adı üzerinde `textDocument/hover` -> `class Deneme` (markdown).
2. Base list'i, sınıf tanım satırındaki `:` sonrası metinden alınır
   (`public class Deneme : MonoBehaviour` -> `MonoBehaviour`).
   Not: Roslyn `typeHierarchy/supertypes` source sınıflarda çalışır, metadata
   base'de boş döner; bu yüzden base identifier üzerinde doğrudan
   `hover` + `definition` kullanılır.
3. Base identifier üzerinde `hover` -> `class UnityEngine.MonoBehaviour`.
   Tam nitelikli ad eşlenir:
   - `UnityEngine.MonoBehaviour` -> `monobehaviour`
   - `UnityEngine.ScriptableObject` -> `scriptableobject`
   - `UnityEditor.Editor` -> `editor`
4. `hover` sonuç vermezse `definition` ile tanım dosyasına gidilir
   (metadata ise dosya adı/URI'den çıkarılır).
5. Base bir proje sınıfıysa (`class Foo : MyBase`) zincir `definition` ile
   en fazla `max_depth = 8` adım takip edilir.
6. Çözülemeyen zincir -> fallback.

İstekler eşzamanlı, toplam süre `timeout_ms` (varsayılan 1500 ms) ile
sınırlandırılır. Timeout/hata -> fallback sonucu korunur.

### 5.3 Mevcut metotlar (LSP)

`documentSymbol` çocuklarındaki `kind == Method` (6) düğümlerinin adları
normalize edilir:

```
"Start() : void"  ->  "Start"
"OnCollisionEnter(Collision)"  ->  "OnCollisionEnter"
```

`detail` ve `name` alanlarındaki ilk `(` öncesi kısım kullanılır.

### 5.4 Fallback (LSP yok / timeout)

Buffer metni üzerinde satır bazlı regex:

- Sınıf: `^%s*[%w_]*%s*class%s+([%w_]+)%s*:?%s*(.*)$`
- Base list: `:` sonrası ilk tanımlayıcı; birden fazla base varsa ilk.
- Tür eşlemesi: tam ad veya kısa ad (`MonoBehaviour`, `ScriptableObject`,
  `Editor`).
- Metotlar: `^%s*[%w_<>%[%],%s]+%s+([%w_]+)%s*%(` — `class`/`struct`/
  `interface`/`new`/`return` hariç.
- Kapsam: imleç, sınıf satırı ile buffer son sınıf kapanışı arasında olmalı.

Fallback dolaylı kalıtımı çözmez. Bu bilinen ve kabul edilen sınır.

### 5.5 Cache

- Kayıt buffer başına: `{ tick, kinds = { [class_key] = kind } }`.
  `class_key = class_name .. ":" .. class_range.start_line` (`start_line`
  0-based). Aynı dosyadaki iç içe veya kardeş sınıflar ayrı anahtar taşır;
  imleç düzenleme olmadan sınıflar arasında gezebilir.
- Geçerlilik: `vim.api.nvim_buf_get_changedtick(bufnr)`.
  `changedtick` değişince kayıt geçersiz; yeniden çözülür.
- Fallback context her çağrıda yeniden hesaplanır; cache yalnız LSP'nin
  çözdüğü `class_kind` değerini sınıf anahtarı altında saklar. Cache'te
  anahtar varsa context'e `source = "lsp"` olarak eklenir.
- Geç gelen LSP cevabı, istek atılırken yakalanan sınıf anahtarına karşı
  doğrulanır: cevabın `class_name` ve `class_range.start_line` değerleri
  istek anındakiyle aynı olmalı. LSP sınıfı cevap anında imleç konumundan
  seçtiği için imleç taşınmışsa cevap başka sınıfa aittir; saklanmaz, yalnız
  kendi `pending` işareti temizlenir (diğer sınıflarınki korunur) ve sonraki
  `resolve` yeniden istek açar.
- `BufWipeout` / `BufDelete` -> kayıt silinir.
- Cache yalnız tamamlanmış bağlamları tutar; bekleyen istekler için sınıf
  anahtarı başına `pending` işareti tutulur, aynı tick'te tekrar istek
  açılmaz (atılan cevap hariç).

## 6. Mesaj Veri Modeli

```lua
---@class unitykit.Message
---@field name string             -- "OnCollisionEnter"
---@field params string|nil      -- "Collision collision"
---@field returns string|nil     -- nil => void
---@field modifiers string|nil   -- "public override" gibi zorunlu ek
---@field doc string             -- tek satır açıklama
---@field order integer|nil      -- isteğe bağlı sıralama
```

Örnekler:

```lua
{ name = "Start", doc = "İlk karede, Update'ten önce bir kez çağrılır." }
{ name = "OnCollisionEnter", params = "Collision collision", doc = "..." }
{ name = "OnInspectorGUI", modifiers = "public override", doc = "..." }
{ name = "RequiresConstantRepaint", returns = "bool", modifiers = "public override" }
```

`modifiers` neden var: `Editor.OnInspectorGUI` gerçek bir override'dır ve
erişim belirteci olmadan (`override void`) derlenmez. Bu yüzden override
gerektiren Editor mesajları `public override` (`OnHeaderGUI` için
`protected override`) taşır; `access` ayarı bunları ezmez. Yaşam döngüsü
mesajları ve `OnSceneGUI` native dispatch'tir, modifiers taşımaz.

### 6.1 Snippet üretimi

Gövde `block` (varsayılan):

```csharp
void Start()
{
    $0
}
```

Gövde `line`:

```csharp
void Start() { $0 }
```

Parametre alan mesaj:

```csharp
void OnCollisionEnter(Collision collision)
{
    $0
}
```

Erişim:

- `access = "none"` -> `void Start()`
- `access = "private"` -> `private void Start()`
- `access = "public"` -> `public void Start()`
- `access = "protected"` -> `protected void Start()`
- `modifiers` doluysa `access` yerine `modifiers` kullanılır.

Girinti: cmp'nin snippet motoru (`vim.snippet.expand`) mevcut satır
girintisini uygular; eklenti sabit girinti eklemez.

### 6.2 Mesaj setleri

**MonoBehaviour**

Yaşam döngüsü: `Awake`, `OnEnable`, `Start`, `FixedUpdate`, `Update`,
`LateUpdate`, `OnDisable`, `OnDestroy`, `OnValidate`, `Reset`

Fizik: `OnCollisionEnter(Collision collision)`,
`OnCollisionStay(Collision collision)`, `OnCollisionExit(Collision collision)`,
`OnTriggerEnter(Collider other)`, `OnTriggerStay(Collider other)`,
`OnTriggerExit(Collider other)`,
`OnControllerColliderHit(ControllerColliderHit hit)`,
`OnParticleCollision(GameObject other)`

Fare: `OnMouseEnter`, `OnMouseOver`, `OnMouseExit`, `OnMouseDown`,
`OnMouseUp`, `OnMouseUpAsButton`, `OnMouseDrag`

Görsel/UI: `OnGUI`, `OnDrawGizmos`, `OnDrawGizmosSelected`,
`OnBecameVisible`, `OnBecameInvisible`

Uygulama: `OnApplicationFocus(bool hasFocus)`,
`OnApplicationPause(bool pauseStatus)`, `OnApplicationQuit`

Dönüşüm: `OnTransformChildrenChanged`, `OnTransformParentChanged`

Ses: `OnAudioFilterRead(float[] data, int channels)`

**ScriptableObject**

`Awake`, `OnEnable`, `OnDisable`, `OnDestroy`, `OnValidate`, `Reset`

**Editor** (`UnityEditor.Editor`)

`Awake`, `OnEnable`, `OnDisable`, `OnDestroy`, `OnValidate`, `Reset`,
`OnInspectorGUI`, `OnSceneGUI`, `OnHeaderGUI`, `HasPreviewGUI`,
`OnPreviewGUI(Rect r, GUIStyle background)`,
`OnInteractivePreviewGUI(Rect r, GUIStyle background)`,
`RequiresConstantRepaint`

Yaşam döngüsü (`Awake`, `OnEnable`, `OnDisable`, `OnDestroy`, `OnValidate`,
`Reset`) native message dispatch'tir; modifiers taşımaz. `OnSceneGUI` da
managed virtual değildir; modifiers taşımaz. `OnInspectorGUI`, `HasPreviewGUI`,
`OnPreviewGUI`, `OnInteractivePreviewGUI`, `RequiresConstantRepaint`
`public override` taşır; `OnHeaderGUI` `protected override` taşır.
`HasPreviewGUI` ve `RequiresConstantRepaint` `bool` döner.

## 7. Completion Davranışı

### 7.1 Aktiflik koşulları

Hepsi sağlanmalı:

- `vim.bo.filetype` `config.filetypes` içinde (varsayılan `{ "cs" }`)
- `unitykit.project.root(bufnr)` bulunabilir
- Buffer değiştirilebilir (`modifiable`, `buftype == ""`)
- İmleç bir sınıf gövdesi içinde (metot gövdesi değil)

Unity projesi bulunamazsa source `{}` döner (sessiz).

### 7.2 Sınıf gövdesi kontrolü

İmleç `class_start` ile `class_end` arasında olmalı. İç içe sınıf varsa en
içteki sınıfın aralığı kullanılır.

Metot içinde öneri çıkmaması için: `documentSymbol`/regex ile bulunan metot
`range`'leri içinde kalan imleç -> boş liste. (Faz 1'de basit yaklaşım: sınıf
gövdesindeki metot aralıkları da cache'lenir.)

### 7.3 Filtreleme

- `hide_implemented = true` -> `implemented` içindeki adlar çıkarılır
  (büyük/küçük harf duyarlı).
- Yazılan önek `nvim-cmp` tarafından filtrelenir; eklenti ayrıca filtrelemez.
- Mesaj listesi tür yoksa boş döner (Unity projesi olsa bile).

### 7.4 cmp source

```lua
source.register("unitykit", {
  name = "unitykit",
  priority = 1000,           -- config.priority -> 1000, aksi halde 500
  keyword_pattern = [[\%([A-Za-z_][A-Za-z0-9_]*\)\?]],
  get_trigger_characters = function() return {} end,
  complete = function(params, callback) ... end,
})
```

- `is_available = function() return has_words_before() end` (cmp helper'ı
  yoksa eklenti kendi kontrolünü yapar).
- `complete` asla `vim.wait` ile bloklamaz; LSP bekleniyorsa fallback
  sonucu döner.
- `callback({ items = ..., isIncomplete = false })`.

### 7.5 Item biçimi

```lua
{
  word = "Start",
  label = "Start()",
  kind = cmp.lsp.CompletionItemKind.Snippet,
  insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
  insertText = "void Start()\n{\n    $0\n}",
  detail = "Unity Message",
  documentation = { kind = "markdown", value = "..." },
  sortText = "0" .. name,   -- priority = true
  filterText = name,
  preselect = true,
}
```

`preselect = true` ilk Unity item'ının menüde işaretli gelmesini sağlar
(`get_selected_entry()` dolu olur). `get_active_entry()` bundan etkilenmez;
`<CR>` gibi onay mapping'leri `cmp.confirm({ select = true })` kullanmalıdır.

`documentation` içeriği:

```markdown
**Start** — İlk karede, Update'ten önce bir kez çağrılır.

```csharp
void Start()
```
```

`sortText` öneki `"0"` -> Unity mesajları LSP önerilerinin üstünde.
`priority = false` -> `sortText` nil.

## 8. Ayarlar

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

- `setup()` birden fazla çağrılabilir; son çağrı geçerlidir, source yeniden
  kaydedilmez (çift kayıt koruması).
- Geçersiz `body`/`access` değeri -> varsayılana döner + `vim.notify` uyarı.

## 9. Proje Tespiti

`unitykit.project.root(bufnr)` yukarı doğru yürür:

1. `ProjectSettings/ProjectVersion.txt` **ve** `Assets/` aynı dizinde -> kök.
2. Bulunamazsa `nil`.
3. Sonuç buffer başına cache'lenir (`BufWipeout` temizler).

`ProjectVersion.txt` zorunlu çünkü sadece `Assets/` klasörü olan C# repo'ları
ve Unity paketleri yanlış pozitif üretir.

## 10. Health

`:checkhealth unitykit` çıktısı:

- Neovim sürümü (>= 0.10)
- `nvim-cmp` yüklü mü
- Kayıtlı `unitykit` source var mı
- Aktif buffer'da Unity kökü
- Aktif buffer'da C# LSP client ve adı
- Son bağlam kaynağı (`lsp` / `fallback`) ve sınıf türü

## 11. Test Stratejisi

Headless, `-u NONE`, fixture tabanlı. Unity kurulumu ve LSP gerekmez.

`tests/run.sh`: `tests/*_spec.lua` dosyalarını sırayla
`nvim --headless -u NONE -l <spec>` ile çalıştırır, ilk hatada çıkar.

| Spec | Kapsam |
|---|---|
| `project_spec.lua` | Kök tespiti, `Assets` tek başına yetersiz, üst dizin yürüme |
| `messages_spec.lua` | Tür -> liste, isim indeksi, çift kayıt yok, set içerikleri |
| `context_spec.lua` | Fallback sınıf/tür/metot tespiti, iç içe sınıf, metot içi |
| `completion_spec.lua` | Snippet üretimi (block/line, access, modifiers, params), sortText, doküman |
| `source_spec.lua` | Guard'lar, hide_implemented, boş tür, cmp yokken hata vermeme |
| `cache_spec.lua` | changedtick geçersizleştirme, BufWipeout temizliği |

LSP yolu `context.lsp` içinde saf fonksiyonlara ayrılır
(`build_type_map`, `parse_hover_base`, `normalize_method_name`) ve bunlar
LSP'siz test edilir. Gerçek LSP entegrasyonu manuel doğrulanır (Roslyn).

## 12. Riskler

| Risk | Etki | Önlem |
|---|---|---|
| Roslyn hover biçimi sürümle değişir | Tür tespiti düşer | Birden fazla desen + fallback |
| `documentSymbol` yavaş (büyük dosya) | Gecikme | Cache + timeout + fallback |
| Editor `override` kuralı gözden kaçar | Derlenmeyen kod | `modifiers` alanı + test |
| Snippet girintisi bozulur | Kötü UX | `vim.snippet` varsayılanına güven, test |
| Unity proje kökü yanlış bulunur | Yanlış öneri | `ProjectVersion.txt` + `Assets/` birlikte |
| `blink.cmp` kullanıcısı | Çalışmaz | README'de açık uyarı; Faz 2 adaptör |

## 13. Kabul Kriterleri

1. `tests/run.sh` tüm spec'leri geçer.
2. Gerçek Unity projesinde (`My project/Assets/Scripts/Deneme.cs`):
   - `Sta` -> `Start` önerisi, seçince blok gövde.
   - `OnCol` -> üç collision mesajı doğru imza ile.
   - Var olan `Start` tekrar önerilmez.
   - `Update` metodunun içinde öneri çıkmaz.
   - `ScriptableObject` sınıfında `Start` çıkmaz.
3. Roslyn kapatıldığında doğrudan `: MonoBehaviour` için çalışır.
4. `:checkhealth unitykit` anlamlı durum gösterir.
5. Kurulum tek `dependencies = { "hrsh7th/nvim-cmp" }` ile çalışır.
