# AGENTS.md — unitykit.nvim

Neovim eklentisi. Faz 1: Unity message completion.

## Önce oku

1. `docs/superpowers/specs/2026-10-27-unitykit-completion-design.md` — tasarım, kararlar, kapsam.
2. `docs/superpowers/plans/2026-10-27-unitykit-completion.md` — uygulama planı, task task.

Plan dışına çıkma. Kapsam büyütme (debugger, analyzer, syntax, code lens yok).

## Komutlar

```bash
tests/run.sh                          # tüm spec'ler
nvim --headless -u NONE -l tests/config_spec.lua   # tek spec
```

Testler Unity kurulumu ve LSP gerektirmez. Her task sonunda `tests/run.sh` çalışır.

## Kurallar

- Neovim >= 0.10. `vim.snippet`, `vim.lsp.get_clients`, `vim.fs` kullanılabilir.
- Tek zorunlu bağımlılık: `hrsh7th/nvim-cmp`. LuaSnip, treesitter, Mason, Neovide, nvim-lspconfig **ekleme**.
- `require("cmp")` yalnız `lua/unitykit/completion/cmp.lua` içinde, `pcall` ile ve çalışma zamanında çağrılır.
- Lua modül adı `unitykit`. Yeni dosyalar `lua/unitykit/` altına.
- 2 boşluk girinti, `stylua.toml` kuralları, satır genişliği 100.
- Satır numaraları içeride 0-based; `end_line` dahil.
- Testler `-u NONE` + repo kökünden; `vim.opt.runtimepath:prepend(root)`.
- Kullanıcı config'ine dokunma (`~/.config/nvim`). Kurulum doğrulaması kullanıcı tarafından yapılır.

## Dosya haritası

| Dosya | Sorumluluk |
|---|---|
| `lua/unitykit/init.lua` | `setup()`, cmp source kaydı |
| `lua/unitykit/config.lua` | Varsayılanlar, doğrulama |
| `lua/unitykit/project.lua` | Unity kökü tespiti |
| `lua/unitykit/messages/` | Bundled mesaj tabloları |
| `lua/unitykit/context/` | Bağlam: LSP, fallback, cache |
| `lua/unitykit/completion/` | cmp source + snippet/item |
| `lua/unitykit/health.lua` | `:checkhealth` |

## Commit

Conventional Commits, küçük commitler, her task sonunda bir commit. Mesaj İngilizce.

## Bitmiş sayılma

- `tests/run.sh` temiz (exit 0).
- Plan task'larının checkbox'ları işaretli.
- Faz 1 kabul kriterleri (spec §13) karşılanmış.
