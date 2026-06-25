local config = require("ano.config")
local storage = require("ano.storage")
local util = require("ano.util")

local M = {}

local namespace = vim.api.nvim_create_namespace("ano")

local function marker_text(annotation)
  local suffix = ""
  if annotation.status == "resolved" then
    suffix = " resolved"
  elseif util.is_stale(annotation) then
    suffix = " stale"
  end

  return string.format(" %s%s: %s", annotation.id, suffix, util.first_comment_line(annotation.comment))
end

local function annotation_matches_buffer(annotation, bufnr)
  local file = util.buf_file(bufnr)
  return file ~= "" and annotation.file == file
end

function M.refresh(bufnr)
  if not config.get().virtual_text then
    return
  end

  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return
  end

  for _, annotation in ipairs(storage.all()) do
    if annotation_matches_buffer(annotation, bufnr) then
      local line = math.max(0, math.min(line_count - 1, (annotation.start_line or 1) - 1))
      local highlight = annotation.status == "resolved" and "Comment" or "WarningMsg"
      vim.api.nvim_buf_set_extmark(bufnr, namespace, line, 0, {
        virt_text = { { marker_text(annotation), highlight } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end
  end
end

function M.refresh_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    M.refresh(bufnr)
  end
end

return M
