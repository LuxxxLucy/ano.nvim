if vim.g.loaded_ano == 1 then
  return
end

vim.g.loaded_ano = 1

local opts = {}

if vim.g.ano_default_keymaps == 0 then
  opts.default_keymaps = false
end

require("ano").setup(opts)
