# AGENTS.md — unitykit.nvim

## Önce oku

Bu repoda çalışırken geçerli fazın spec ve planını oku:

- `docs/superpowers/specs/` — tasarım, kararlar, kapsam
- `docs/superpowers/plans/` — uygulama sırası

Plan dışına çıkma. Yeni kapsam gerekiyorsa önce spec'i güncelle.

## Komutlar

```bash
tests/run.sh                                        # tüm spec'ler
nvim --headless -u NONE -l tests/<name>_spec.lua    # tek spec
```

Testler Unity kurulumu ve LSP gerektirmez.

## Değişmez kurallar

- Neovim >= 0.10 hedeflenir.
- Tek zorunlu bağımlılık `hrsh7th/nvim-cmp`. LuaSnip, treesitter, Mason, Neovide, nvim-lspconfig ekleme.
- `require("cmp")` yalnız `lua/unitykit/completion/cmp.lua` içinde, `pcall` ile ve modül yüklenirken değil çalışma zamanında çağrılır.
- Lua modül adı `unitykit`; dosyalar `lua/unitykit/` altında.
- 2 boşluk girinti, `stylua.toml`, satır genişliği 100.
- Satır numaraları içeride 0-based; `end_line` dahil.
- Testler `-u NONE`, repo kökünden, `vim.opt.runtimepath:prepend(root)` ile.
- Kullanıcının Neovim config'ine (`~/.config/nvim`) dokunma.
- Conventional Commits, İngilizce mesaj, her task sonunda bir commit.

## Bitmiş sayılma

- `tests/run.sh` exit 0.
- Plan task checkbox'ları işaretli.
