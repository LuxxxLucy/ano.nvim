local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local state_dir = vim.fn.tempname()
local review_md = state_dir .. "/review.md"
local sample = state_dir .. "/sample.lua"

vim.fn.mkdir(state_dir, "p")
vim.opt.directory = state_dir .. "//"
vim.opt.backupdir = state_dir .. "//"
vim.opt.viewdir = state_dir
vim.opt.undodir = state_dir
vim.opt.swapfile = false
vim.fn.writefile({
  "local x = 1",
  "local y = x + 1",
  "return y",
}, sample)

require("ano").setup({ state_dir = state_dir, default_keymaps = false })

local function assert_true(value, message)
  if not value then
    error(message, 2)
  end
end

local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

assert_true(vim.fn.exists(":AnoAdd") == 2, "AnoAdd command missing")
assert_true(vim.fn.exists(":AnoSave") == 2, "AnoSave command missing")

vim.cmd.edit(sample)
vim.cmd("1")
vim.cmd("AnoAdd current line note")
vim.cmd("2,3AnoAdd range note")
vim.api.nvim_win_set_cursor(0, { 1, 6 })
vim.api.nvim_feedkeys("v" .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
vim.cmd("'<,'>AnoAdd word note")
local annotations = require("ano.storage").all()
assert_true(annotations[3].code == "x", "word annotation should store selected text only")
assert_true(annotations[3].selection_mode == "char", "word annotation should use char selection mode")

vim.cmd("AnoList")
assert_true(#vim.fn.getqflist() == 3, "quickfix list should contain three annotations")

vim.cmd("AnoPreview")
assert_true(vim.api.nvim_buf_get_name(0) == "ano://preview", "preview buffer name mismatch")

vim.cmd.edit(sample)
vim.cmd("AnoResolve Ano1")
vim.cmd("AnoResolve Ano3")
vim.cmd("AnoSave " .. vim.fn.fnameescape(review_md))

local markdown = read(review_md)
assert_true(markdown:find("range note", 1, true) ~= nil, "Markdown export missing open annotation")
assert_true(markdown:find("current line note", 1, true) == nil, "Markdown export included resolved annotation")
assert_true(markdown:find("word note", 1, true) == nil, "Markdown export included resolved word annotation")
assert_true(markdown:find("local y = x + 1", 1, true) ~= nil, "Markdown export missing selected code")

vim.cmd("AnoReopen Ano1")
vim.cmd("AnoDelete Ano2")
vim.cmd("AnoDelete Ano3")
vim.cmd("AnoSave " .. vim.fn.fnameescape(review_md))

markdown = read(review_md)
assert_true(markdown:find("current line note", 1, true) ~= nil, "reopened annotation missing")
assert_true(markdown:find("range note", 1, true) == nil, "deleted annotation still exported")

vim.cmd("AnoStatus")
vim.cmd("AnoYank")
vim.cmd("qa!")
