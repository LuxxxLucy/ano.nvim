local config = require("ano.config")
local export = require("ano.export")
local marks = require("ano.marks")
local storage = require("ano.storage")
local ui = require("ano.ui")
local util = require("ano.util")

local M = {}

local jump_to
local quickfix_title = "Ano annotations"

local function quickfix_window_open()
  for _, info in ipairs(vim.fn.getwininfo()) do
    if info.quickfix == 1 and info.loclist == 0 then
      return true
    end
  end

  return false
end

local function focus_regular_window()
  if vim.bo.buftype ~= "quickfix" then
    return
  end

  for _, info in ipairs(vim.fn.getwininfo()) do
    if info.quickfix == 0 and info.loclist == 0 and vim.api.nvim_win_is_valid(info.winid) then
      vim.api.nvim_set_current_win(info.winid)
      return
    end
  end
end

local function quickfix_annotation_under_cursor()
  if vim.bo.buftype ~= "quickfix" then
    return nil
  end

  local index = vim.api.nvim_win_get_cursor(0)[1]
  local ok, quickfix = pcall(vim.fn.getqflist, { items = 0 })
  if not ok or type(quickfix) ~= "table" or type(quickfix.items) ~= "table" then
    return nil
  end

  local item = quickfix.items[index]
  if not item then
    return nil
  end

  local user_data = item.user_data
  if type(user_data) == "table" and user_data.ano_id then
    return storage.find(user_data.ano_id)
  end

  local id = item.text and item.text:match("^(%S+)")
  return storage.find(id)
end

local function annotation_under_cursor()
  local quickfix_annotation = quickfix_annotation_under_cursor()
  if quickfix_annotation then
    return quickfix_annotation
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file = util.buf_file(bufnr)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local best

  for _, annotation in ipairs(storage.all()) do
    if annotation.file == file and line >= annotation.start_line and line <= annotation.end_line then
      if not best or (annotation.end_line - annotation.start_line) < (best.end_line - best.start_line) then
        best = annotation
      end
    end
  end

  return best
end

local function resolve_target(id)
  if id and id ~= "" then
    local annotation = storage.find(id)
    if not annotation then
      util.notify("annotation not found: " .. id, vim.log.levels.ERROR)
    end
    return annotation
  end

  local annotation = annotation_under_cursor()
  if not annotation then
    util.notify("no annotation under cursor", vim.log.levels.ERROR)
  end
  return annotation
end

local function save_and_refresh()
  storage.save()
  marks.refresh_all()
  if quickfix_window_open() then
    M.list_command(false)
  end
end

local function annotation_after(candidate, annotation)
  if (candidate.file or "") ~= (annotation.file or "") then
    return (candidate.file or "") > (annotation.file or "")
  end
  if (candidate.start_line or 0) ~= (annotation.start_line or 0) then
    return (candidate.start_line or 0) > (annotation.start_line or 0)
  end
  return (candidate.id or "") > (annotation.id or "")
end

local function next_open_after(annotation)
  local annotations = {}

  for _, candidate in ipairs(storage.all()) do
    if candidate.status ~= "resolved" then
      table.insert(annotations, candidate)
    end
  end

  annotations = util.sort_annotations(annotations)
  if #annotations == 0 then
    return nil
  end

  for _, candidate in ipairs(annotations) do
    if annotation_after(candidate, annotation) then
      return candidate
    end
  end

  return annotations[1]
end

local function add_annotation(selection, comment)
  local trimmed = util.trim(comment)
  if trimmed == "" then
    util.notify("empty annotation comment", vim.log.levels.WARN)
    return
  end

  local now = util.now()
  local annotation = {
    id = storage.next_id(),
    file = selection.file,
    relfile = selection.relfile,
    start_line = selection.start_line,
    end_line = selection.end_line,
    start_col = selection.start_col,
    end_col = selection.end_col,
    selection_mode = selection.selection_mode,
    code = selection.code,
    comment = comment,
    status = "open",
    created_at = now,
    updated_at = now,
  }

  storage.add(annotation)
  marks.refresh(selection.bufnr)
  if quickfix_window_open() then
    M.list_command(false)
  end
  util.notify(string.format("added %s", annotation.id))
end

function M.add_command(opts)
  local selection = util.selection_from_command(opts)
  local comment = opts.args or ""

  if util.trim(comment) ~= "" then
    add_annotation(selection, comment)
    return
  end

  ui.open_input({
    title = "Ano Add",
    on_confirm = function(text)
      add_annotation(selection, text)
    end,
  })
end

function M.edit_command(opts)
  local annotation = resolve_target(opts.args)
  if not annotation then
    return
  end

  ui.open_input({
    title = "Ano Edit " .. annotation.id,
    initial_text = annotation.comment,
    on_confirm = function(text)
      annotation.comment = text
      annotation.updated_at = util.now()
      if annotation.status == "resolved" then
        annotation.status = "open"
        annotation.resolved_at = nil
      end
      save_and_refresh()
      util.notify("updated " .. annotation.id)
    end,
  })
end

function M.delete_command(opts)
  local annotation = resolve_target(opts.args)
  if not annotation then
    return
  end

  storage.delete(annotation.id)
  marks.refresh_all()
  if quickfix_window_open() then
    M.list_command(false)
  end
  util.notify("deleted " .. annotation.id)
end

function M.resolve_command(opts)
  local annotation = resolve_target(opts.args)
  if not annotation then
    return
  end

  annotation.status = "resolved"
  annotation.resolved_at = util.now()
  annotation.updated_at = annotation.resolved_at
  save_and_refresh()
  util.notify("resolved " .. annotation.id)

  local next_annotation = next_open_after(annotation)
  if next_annotation then
    jump_to(next_annotation)
  end
end

function M.reopen_command(opts)
  local annotation = resolve_target(opts.args)
  if not annotation then
    return
  end

  annotation.status = "open"
  annotation.resolved_at = nil
  annotation.updated_at = util.now()
  save_and_refresh()
  util.notify("reopened " .. annotation.id)
end

local function quickfix_item_text(annotation)
  local status = annotation.status == "resolved" and " [resolved]" or ""
  return string.format("%s%s %s %s", annotation.id, status, util.location(annotation), util.first_comment_line(annotation.comment))
end

function M.list_command(open)
  local items = {}

  for _, annotation in ipairs(util.sort_annotations(vim.deepcopy(storage.all()))) do
    table.insert(items, {
      filename = annotation.file ~= "" and annotation.file or nil,
      lnum = annotation.start_line,
      end_lnum = annotation.end_line,
      text = quickfix_item_text(annotation),
      user_data = { ano_id = annotation.id },
    })
  end

  vim.fn.setqflist({}, " ", {
    title = quickfix_title,
    items = items,
  })

  if open ~= false then
    vim.cmd.copen()
  end
end

local function navigable_annotations()
  local annotations = {}

  for _, annotation in ipairs(storage.all()) do
    if annotation.status ~= "resolved" then
      table.insert(annotations, annotation)
    end
  end

  if #annotations == 0 then
    annotations = vim.deepcopy(storage.all())
  end

  return util.sort_annotations(annotations)
end

jump_to = function(annotation)
  if not annotation then
    util.notify("no annotations", vim.log.levels.WARN)
    return
  end

  focus_regular_window()

  if annotation.file and annotation.file ~= "" then
    vim.cmd.edit(vim.fn.fnameescape(annotation.file))
  end

  local line = math.max(1, math.min(annotation.start_line, vim.api.nvim_buf_line_count(0)))
  vim.api.nvim_win_set_cursor(0, { line, math.max(0, (annotation.start_col or 1) - 1) })
  vim.cmd.normal({ args = { "zz" }, bang = true })
end

function M.next_command()
  local annotations = navigable_annotations()
  if #annotations == 0 then
    util.notify("no annotations", vim.log.levels.WARN)
    return
  end

  local file = util.buf_file(0)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, annotation in ipairs(annotations) do
    if annotation.file > file or (annotation.file == file and annotation.start_line > line) then
      jump_to(annotation)
      return
    end
  end

  jump_to(annotations[1])
end

function M.prev_command()
  local annotations = navigable_annotations()
  if #annotations == 0 then
    util.notify("no annotations", vim.log.levels.WARN)
    return
  end

  local file = util.buf_file(0)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for index = #annotations, 1, -1 do
    local annotation = annotations[index]
    if annotation.file < file or (annotation.file == file and annotation.start_line < line) then
      jump_to(annotation)
      return
    end
  end

  jump_to(annotations[#annotations])
end

function M.status_command()
  local open = 0
  local resolved = 0
  local stale = 0

  for _, annotation in ipairs(storage.all()) do
    if annotation.status == "resolved" then
      resolved = resolved + 1
    else
      open = open + 1
    end

    if util.is_stale(annotation) then
      stale = stale + 1
    end
  end

  util.notify(string.format("Ano: %d open, %d resolved, %d stale", open, resolved, stale))
end

function M.clear_command()
  local total = #storage.all()
  if total == 0 then
    util.notify("no annotations")
    return
  end

  local resolved = 0
  for _, annotation in ipairs(storage.all()) do
    if annotation.status == "resolved" then
      resolved = resolved + 1
    end
  end

  -- Offer "resolved only" only when there is something resolved to clear.
  -- Each menu entry maps directly to the action it names; no index juggling.
  local actions, prompt
  if resolved > 0 then
    actions = { "resolved", "all", "cancel" }
    prompt = string.format("Clear annotations? %d resolved, %d total.", resolved, total)
  else
    actions = { "all", "cancel" }
    prompt = string.format("Clear all %d annotations?", total)
  end

  local labels = ({ resolved = "&Resolved only", all = "&All", cancel = "&Cancel" })
  local menu = vim.tbl_map(function(a) return labels[a] end, actions)
  local action = actions[vim.fn.confirm(prompt, table.concat(menu, "\n"), #actions)]

  if action == "resolved" then
    util.notify(string.format("cleared %d resolved annotations", storage.clear_resolved()))
    marks.refresh_all()
    if quickfix_window_open() then
      M.list_command(false)
    end
  elseif action == "all" then
    util.notify(string.format("cleared %d annotations", storage.clear_all()))
    marks.refresh_all()
    if quickfix_window_open() then
      M.list_command(false)
    end
  else
    util.notify("clear cancelled")
  end
end

local function create_commands()
  local commands = {
    AnoAdd = { function(opts) M.add_command(opts) end, { nargs = "*", range = true, desc = "Add an Ano annotation" } },
    AnoEdit = { function(opts) M.edit_command(opts) end, { nargs = "?", desc = "Edit an Ano annotation" } },
    AnoDelete = { function(opts) M.delete_command(opts) end, { nargs = "?", desc = "Delete an Ano annotation" } },
    AnoResolve = { function(opts) M.resolve_command(opts) end, { nargs = "?", desc = "Resolve an Ano annotation" } },
    AnoReopen = { function(opts) M.reopen_command(opts) end, { nargs = "?", desc = "Reopen an Ano annotation" } },
    AnoList = { function() M.list_command() end, { desc = "List Ano annotations in quickfix" } },
    AnoNext = { function() M.next_command() end, { desc = "Jump to next Ano annotation" } },
    AnoPrev = { function() M.prev_command() end, { desc = "Jump to previous Ano annotation" } },
    AnoPreview = { function() export.open_preview() end, { desc = "Open Ano Markdown preview" } },
    AnoSave = { function(opts) export.write_markdown(opts.args) end, { nargs = "?", complete = "file", desc = "Save Ano Markdown" } },
    AnoYank = { function() export.yank() end, { desc = "Copy Ano Markdown" } },
    AnoClear = { function() M.clear_command() end, { desc = "Clear Ano annotations" } },
    AnoStatus = { function() M.status_command() end, { desc = "Show Ano annotation counts" } },
  }

  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command[1], vim.tbl_extend("force", command[2], { force = true }))
  end
end

local function create_keymaps()
  local maps = {
    { "n", "<leader>aa", "<cmd>AnoAdd<CR>", "Add Ano annotation" },
    { "x", "<leader>aa", ":'<,'>AnoAdd<CR>", "Add Ano annotation" },
    { "n", "<leader>ae", "<cmd>AnoEdit<CR>", "Edit Ano annotation" },
    { "n", "<leader>ad", "<cmd>AnoDelete<CR>", "Delete Ano annotation" },
    { "n", "<leader>ar", "<cmd>AnoResolve<CR>", "Resolve Ano annotation" },
    { "n", "<leader>ao", "<cmd>AnoReopen<CR>", "Reopen Ano annotation" },
    { "n", "<leader>al", "<cmd>AnoList<CR>", "List Ano annotations" },
    { "n", "<leader>an", "<cmd>AnoNext<CR>", "Next Ano annotation" },
    { "n", "<leader>ap", "<cmd>AnoPrev<CR>", "Previous Ano annotation" },
    { "n", "<leader>av", "<cmd>AnoPreview<CR>", "Preview Ano annotations" },
    { "n", "<leader>as", "<cmd>AnoSave<CR>", "Save Ano Markdown" },
    { "n", "<leader>ay", "<cmd>AnoYank<CR>", "Yank Ano Markdown" },
    { "n", "<leader>ac", "<cmd>AnoClear<CR>", "Clear Ano annotations" },
    { "n", "<leader>at", "<cmd>AnoStatus<CR>", "Ano status" },
  }

  for _, map in ipairs(maps) do
    vim.keymap.set(map[1], map[2], map[3], { silent = true, desc = map[4] })
  end
end

local function create_autocmds()
  local group = vim.api.nvim_create_augroup("Ano", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      marks.refresh(args.buf)
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  storage.load()
  create_commands()
  create_autocmds()

  if config.get().default_keymaps then
    create_keymaps()
  end

  marks.refresh_all()
end

return M
