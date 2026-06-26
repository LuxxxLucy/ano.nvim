# ano

<p align="center">
  <img src="assets/ano-logo.svg" alt="ano logo" width="620">
  <br>
  <sub>Logo generated with GPT, inspired by <a href="https://vuejs.org/?uwu">Vue's <code>?uwu</code> sticker style</a>.</sub>
</p>

Review annotations for Neovim. Comment on code without editing the file. Export as Markdown.

## Install

Neovim 0.8+. Works with no config.

```lua
{ "luxxxlucy/ano.nvim", opts = {} }   -- lazy.nvim
```
```vim
Plug 'luxxxlucy/ano.nvim'             " vim-plug
```

## Use

Sit on a line (or select a range/word), `:AnoAdd`, type a comment, `<leader><CR>`. Repeat. `:AnoSave` writes the Markdown.

Commands take an optional id; without one they hit the annotation under the cursor. Keymaps are `<leader>a` + the letter (`default_keymaps = false` to turn off).

| Command | Key | |
| --- | --- | --- |
| `:AnoAdd [comment]` | `aa` | add to current line/selection |
| `:AnoEdit [id]` | `ae` | edit |
| `:AnoDelete [id]` | `ad` | delete |
| `:AnoResolve [id]` | `ar` | resolve (kept, but out of exports) |
| `:AnoReopen [id]` | `ao` | reopen |
| `:AnoList` | `al` | quickfix list; use space to toggles resolved status |
| `:AnoNext` / `:AnoPrev` | `an` / `ap` | jump between annotations |
| `:AnoPreview` | `av` | Markdown preview buffer |
| `:AnoSave [path]` | `as` | write Markdown |
| `:AnoYank` | `ay` | copy Markdown to clipboard |
| `:AnoClear` | `ac` | clear resolved or all |
| `:AnoStatus` | `at` | counts |

## Config

```lua
require("ano").setup({
  state_dir = vim.fn.stdpath("data") .. "/ano",
  mirror_in_tmp = true,                  -- also copy each export to /tmp/ano
  id_prefix = "Ano",
  default_markdown_path = ".local-review/review.md",
  include_resolved_in_export = false,
  default_keymaps = true,
  virtual_text = true,
})
```

## Storage

One state file per project, `~/.local/share/nvim/ano/<sha256-of-cwd>.json`. Source files are never written. Exports carry each annotation's id, location, status, timestamps, comment, and the code as captured; an annotation goes stale when that code no longer matches the file. With `mirror_in_tmp` the latest export also lands at `/tmp/ano/review.md`.

## Test

```sh
nvim --headless -u NONE -i NONE -c 'luafile tests/smoke.lua'
```

MIT.
