local util = require("ano.util")

local M = {}

local inputs = {}

local function close_input(bufnr)
  local entry = inputs[bufnr]
  if not entry then
    return
  end

  if entry.win and vim.api.nvim_win_is_valid(entry.win) then
    vim.api.nvim_win_close(entry.win, true)
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  inputs[bufnr] = nil
end

function M.confirm(bufnr)
  local entry = inputs[bufnr]
  if not entry or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  if util.trim(text) == "" then
    util.notify("empty annotation comment", vim.log.levels.WARN)
    return
  end

  close_input(bufnr)
  entry.on_confirm(text)
end

function M.cancel(bufnr)
  close_input(bufnr)
end

function M.open_input(opts)
  opts = opts or {}

  local width = math.max(40, math.min(88, math.floor(vim.o.columns * 0.75)))
  local height = math.max(8, math.min(18, math.floor(vim.o.lines * 0.35)))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  if opts.initial_text and opts.initial_text ~= "" then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(opts.initial_text, "\n", { plain = true }))
  end

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    title = " " .. (opts.title or "Ano Comment") .. " ",
    title_pos = "left",
  })

  inputs[bufnr] = {
    win = win,
    on_confirm = opts.on_confirm,
  }

  vim.keymap.set("n", "<leader><CR>", function()
    M.confirm(bufnr)
  end, { buffer = bufnr, silent = true, desc = "Confirm Ano annotation" })

  vim.keymap.set("i", "<leader><CR>", function()
    vim.cmd.stopinsert()
    vim.schedule(function()
      M.confirm(bufnr)
    end)
  end, { buffer = bufnr, silent = true, desc = "Confirm Ano annotation" })

  vim.keymap.set("n", "q", function()
    M.cancel(bufnr)
  end, { buffer = bufnr, silent = true, desc = "Cancel Ano annotation" })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      inputs[bufnr] = nil
    end,
  })

  vim.api.nvim_set_current_win(win)
  vim.cmd.startinsert()
end

return M
