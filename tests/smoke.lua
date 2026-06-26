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

vim.g.mapleader = " "
require("ano").setup({ state_dir = state_dir, default_keymaps = true })

local function assert_true(value, message)
  if not value then
    error(message, 2)
  end
end

local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

local function qf_items()
  return vim.fn.getqflist({ items = 0 }).items
end

local function quickfix_win()
  for _, info in ipairs(vim.fn.getwininfo()) do
    if info.quickfix == 1 and info.loclist == 0 then
      return info.winid
    end
  end
  return nil
end

assert_true(vim.fn.exists(":AnoAdd") == 2, "AnoAdd command missing")
assert_true(vim.fn.exists(":AnoSave") == 2, "AnoSave command missing")

local input_done = false
local input_text
local input_mode
require("ano.ui").open_input({
  initial_text = "edited",
  on_confirm = function(text)
    input_text = text
    input_mode = vim.api.nvim_get_mode().mode
    input_done = true
  end,
})
vim.cmd.stopinsert()
vim.api.nvim_win_set_cursor(0, { 1, 6 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A <CR>", true, false, true), "xt", false)
assert_true(vim.wait(1000, function()
  return input_done
end), "input confirm should run")
assert_true(input_text == "edited", "leader key should not be inserted into confirmed text")
assert_true(input_mode == "n", "input confirm should leave insert mode before confirming")

vim.cmd.edit(sample)
vim.cmd("1")
vim.cmd("AnoAdd current line note")
vim.cmd("2,3AnoAdd range note")
vim.api.nvim_win_set_cursor(0, { 1, 6 })
vim.api.nvim_feedkeys("v" .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
vim.cmd("'<,'>AnoAdd word note")
local annotations = require("ano.storage").all()
local export = require("ano.export")
local util = require("ano.util")
assert_true(annotations[3].code == "x", "word annotation should store selected text only")
assert_true(annotations[3].selection_mode == "char", "word annotation should use char selection mode")

local grouped_markdown = export.markdown()
local sample_header = "# " .. annotations[1].relfile
local sample_header_pos = grouped_markdown:find(sample_header, 1, true)
assert_true(sample_header_pos ~= nil, "Markdown export should group annotations by file")
assert_true(grouped_markdown:find(sample_header, sample_header_pos + 1, true) == nil, "Markdown export should emit one header per file")
assert_true(grouped_markdown:find("## Comment 1 " .. util.location(annotations[1]), 1, true) ~= nil, "Markdown export should include comment location")
assert_true(grouped_markdown:find("## Comment 2 " .. util.location(annotations[2]), 1, true) ~= nil, "Markdown export should include range comment location")
assert_true(grouped_markdown:find("```lua", 1, true) == nil, "Markdown export should use plain code fences")

vim.cmd("AnoList")
local qf_win = quickfix_win()
assert_true(qf_win ~= nil, "quickfix list window should be open")
assert_true(#qf_items() == 3, "quickfix list should contain three annotations")
assert_true(qf_items()[1].text:find("^%[ %]") ~= nil, "quickfix list should show open checkboxes")

vim.cmd.wincmd("p")
vim.cmd("3AnoAdd list refresh note")
assert_true(#qf_items() == 4, "quickfix list should refresh after add")
vim.cmd("AnoDelete Ano4")
assert_true(#qf_items() == 3, "quickfix list should refresh after delete")

vim.api.nvim_set_current_win(qf_win)
vim.api.nvim_win_set_cursor(qf_win, { 1, 0 })
vim.api.nvim_feedkeys(" ar", "mxt", false)
assert_true(vim.wait(1000, function()
  return annotations[1].status == "resolved"
end), "leader resolve should work in quickfix list")
assert_true(qf_items()[1].text:find("^%[x%]") ~= nil, "quickfix list should show resolved checkboxes")
assert_true(qf_items()[1].text:find("[resolved]", 1, true) == nil, "quickfix list should not use text status labels")
assert_true(vim.api.nvim_win_get_cursor(0)[1] == annotations[3].start_line, "quickfix resolve should jump to next open annotation")

vim.api.nvim_set_current_win(qf_win)
vim.api.nvim_win_set_cursor(qf_win, { 1, 0 })
vim.api.nvim_feedkeys(" ", "mxt", false)
assert_true(vim.wait(1000, function()
  return annotations[1].status == "open"
end), "space should reopen quickfix annotation")
assert_true(qf_items()[1].text:find("^%[ %]") ~= nil, "space should refresh open checkbox")
vim.api.nvim_feedkeys(" ", "mxt", false)
assert_true(vim.wait(1000, function()
  return annotations[1].status == "resolved"
end), "space should resolve quickfix annotation")
assert_true(qf_items()[1].text:find("^%[x%]") ~= nil, "space should refresh resolved checkbox")

vim.cmd("AnoPreview")
assert_true(vim.api.nvim_buf_get_name(0) == "ano://preview", "preview buffer name mismatch")

vim.cmd.edit(sample)
vim.cmd("AnoResolve Ano3")
assert_true(vim.api.nvim_win_get_cursor(0)[1] == annotations[2].start_line, "resolve by id should jump from the resolved annotation")
vim.cmd("AnoSave " .. vim.fn.fnameescape(review_md))

local markdown = read(review_md)
assert_true(markdown:find("range note", 1, true) ~= nil, "Markdown export missing open annotation")
assert_true(markdown:find("# " .. annotations[2].relfile, 1, true) ~= nil, "Markdown export should include file header")
assert_true(markdown:find("## Comment 2 " .. util.location(annotations[2]), 1, true) ~= nil, "Markdown export should label annotations as comments")
assert_true(markdown:find("## Ano2 ", 1, true) == nil, "Markdown export should not expose Ano ids in headings")
assert_true(markdown:find("- Status:", 1, true) == nil, "Markdown export should not include status")
assert_true(markdown:find("- Created:", 1, true) == nil, "Markdown export should not include created date")
assert_true(markdown:find("- Updated:", 1, true) == nil, "Markdown export should not include updated date")
assert_true(markdown:find("Selected code:", 1, true) == nil, "Markdown export should not label selected code")
assert_true(markdown:find("Comment:", 1, true) == nil, "Markdown export should not label comments")
assert_true(markdown:find("```lua", 1, true) == nil, "Markdown export should use plain code fences")
assert_true(markdown:find("current line note", 1, true) == nil, "Markdown export included resolved annotation")
assert_true(markdown:find("word note", 1, true) == nil, "Markdown export included resolved word annotation")
assert_true(markdown:find("local y = x + 1", 1, true) ~= nil, "Markdown export missing selected code")
assert_true(markdown:find("```", 1, true) < markdown:find("range note", 1, true), "Markdown export should put code before comment")

vim.cmd("AnoReopen Ano1")
vim.cmd("AnoDelete Ano2")
vim.cmd("AnoDelete Ano3")
vim.cmd("AnoSave " .. vim.fn.fnameescape(review_md))

markdown = read(review_md)
assert_true(markdown:find("current line note", 1, true) ~= nil, "reopened annotation missing")
assert_true(markdown:find("range note", 1, true) == nil, "deleted annotation still exported")

vim.cmd("AnoStatus")
vim.cmd("AnoYank")
vim.cmd("AnoResolve Ano1")
local confirm_menu
local confirm = vim.fn.confirm
vim.fn.confirm = function(_, menu)
  confirm_menu = menu
  return 1
end
vim.cmd("AnoClear")
vim.fn.confirm = confirm
assert_true(confirm_menu:find("Resolved only", 1, true) == nil, "clear should not offer resolved-only when all annotations are resolved")
assert_true(confirm_menu:find("All", 1, true) ~= nil, "clear should offer all when all annotations are resolved")
assert_true(#require("ano.storage").all() == 0, "clear all should remove all resolved annotations")
vim.cmd("qa!")
