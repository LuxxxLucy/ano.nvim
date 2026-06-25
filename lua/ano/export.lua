local config = require("ano.config")
local storage = require("ano.storage")
local util = require("ano.util")

local M = {}

local function copy_annotation(annotation)
  local copied = vim.tbl_extend("force", {}, annotation)
  copied.stale = util.is_stale(annotation)
  copied.location = util.location(annotation)
  return copied
end

local function filtered_annotations(opts)
  opts = opts or {}
  local include_resolved = opts.include_resolved
  if include_resolved == nil then
    include_resolved = config.get().include_resolved_in_export
  end

  local annotations = {}
  for _, annotation in ipairs(storage.all()) do
    if include_resolved or annotation.status ~= "resolved" then
      table.insert(annotations, copy_annotation(annotation))
    end
  end

  return util.sort_annotations(annotations)
end

local function fence_for(text)
  local length = 3
  for ticks in string.gmatch(text or "", "`+") do
    if #ticks >= length then
      length = #ticks + 1
    end
  end
  return string.rep("`", length)
end

local function code_language(annotation)
  if vim.filetype and vim.filetype.match and annotation.file and annotation.file ~= "" then
    local ok, filetype = pcall(vim.filetype.match, { filename = annotation.file })
    if ok and filetype then
      return filetype
    end
  end

  local extension = vim.fn.fnamemodify(annotation.file or "", ":e")
  return extension ~= "" and extension or "text"
end

-- Mirror the latest export to /tmp/ano/<name>, a fixed memorable path,
-- so it can be read or pasted without recalling the per-project export path.
local function mirror(name, lines)
  if not config.get().mirror_in_tmp then
    return
  end
  pcall(vim.fn.mkdir, "/tmp/ano", "p")
  pcall(vim.fn.writefile, lines, "/tmp/ano/" .. name)
end

local function append_text(lines, text)
  for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
    table.insert(lines, line)
  end
end

local function append_code(lines, annotation)
  local fence = fence_for(annotation.code)
  table.insert(lines, fence .. code_language(annotation))
  append_text(lines, annotation.code)
  table.insert(lines, fence)
end

function M.markdown(opts)
  local annotations = filtered_annotations(opts)
  local lines = {
    "# Ano Review Annotations",
    "",
    "- Project: " .. vim.fn.getcwd(),
    "- Generated: " .. util.now(),
    "",
  }

  if #annotations == 0 then
    table.insert(lines, "_No annotations to export._")
    table.insert(lines, "")
    return table.concat(lines, "\n")
  end

  for _, annotation in ipairs(annotations) do
    local status = annotation.status or "open"
    if annotation.stale then
      status = status .. " stale"
    end

    table.insert(lines, string.format("## %s %s", annotation.id, annotation.location))
    table.insert(lines, "")
    table.insert(lines, "- Status: " .. status)
    table.insert(lines, "- Created: " .. (annotation.created_at or ""))
    table.insert(lines, "- Updated: " .. (annotation.updated_at or ""))
    table.insert(lines, "")
    table.insert(lines, "Comment:")
    table.insert(lines, "")
    append_text(lines, annotation.comment)

    table.insert(lines, "")
    table.insert(lines, "Selected code:")
    table.insert(lines, "")
    append_code(lines, annotation)
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

function M.write_markdown(path, opts)
  path = path ~= "" and path or config.get().default_markdown_path
  util.ensure_parent(path)

  local lines = vim.split(M.markdown(opts), "\n", { plain = true })
  local ok, err = pcall(vim.fn.writefile, lines, path)
  if not ok then
    util.notify("failed to write Markdown: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  mirror("review.md", lines)
  util.notify("wrote " .. path)
  return true
end

function M.yank(opts)
  local text = M.markdown(opts)
  local ok = false
  local used_register = "+"

  if vim.fn.has("clipboard") == 1 then
    local set_ok, result = pcall(vim.fn.setreg, "+", text)
    ok = set_ok and result == 0 and vim.v.shell_error == 0
  end

  if not ok then
    used_register = '"'
    ok = pcall(vim.fn.setreg, '"', text)
  end

  mirror("review.md", vim.split(text, "\n", { plain = true }))

  if ok and used_register == "+" then
    util.notify("copied Markdown to + register")
  elseif ok then
    util.notify("clipboard unavailable; copied Markdown to unnamed register", vim.log.levels.WARN)
  else
    util.notify("failed to copy Markdown to any register", vim.log.levels.ERROR)
  end

  return ok
end

function M.open_preview(opts)
  local name = "ano://preview"
  local bufnr

  for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(candidate) and vim.api.nvim_buf_get_name(candidate) == name then
      bufnr = candidate
      break
    end
  end

  if bufnr then
    vim.api.nvim_set_current_buf(bufnr)
  else
    vim.cmd.enew()
    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(bufnr, name)
  end

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(M.markdown(opts), "\n", { plain = true }))
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = true
end

return M
