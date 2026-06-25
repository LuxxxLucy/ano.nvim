local M = {}

function M.now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Ano" })
end

function M.trim(text)
  return vim.trim(text or "")
end

function M.ensure_parent(path)
  local parent = vim.fn.fnamemodify(path, ":p:h")
  if parent ~= "" then
    vim.fn.mkdir(parent, "p")
  end
end

function M.buf_file(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return ""
  end
  return vim.fn.fnamemodify(name, ":p")
end

function M.rel_file(path)
  if path == "" then
    return "[No Name]"
  end
  return vim.fn.fnamemodify(path, ":.")
end

local function ordered_positions(start_pos, end_pos)
  local s_line = start_pos[2]
  local s_col = start_pos[3]
  local e_line = end_pos[2]
  local e_col = end_pos[3]

  if s_line > e_line or (s_line == e_line and s_col > e_col) then
    s_line, e_line = e_line, s_line
    s_col, e_col = e_col, s_col
  end

  return s_line, s_col, e_line, e_col
end

local function slice_visual_text(lines, start_col, end_col)
  if #lines == 0 then
    return ""
  end

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
    return table.concat(lines, "\n")
  end

  lines[1] = string.sub(lines[1], start_col)
  lines[#lines] = string.sub(lines[#lines], 1, end_col)
  return table.concat(lines, "\n")
end

function M.selection_from_command(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local range = opts.range or 0
  local start_line
  local end_line
  local start_col
  local end_col
  local selection_mode = "line"

  if range > 0 then
    start_line = opts.line1
    end_line = opts.line2
  else
    start_line = vim.api.nvim_win_get_cursor(0)[1]
    end_line = start_line
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local code = table.concat(lines, "\n")

  if range > 0 and vim.fn.visualmode() == "v" then
    local visual_start = vim.fn.getpos("'<")
    local visual_end = vim.fn.getpos("'>")
    local start_buf = visual_start[1]
    local end_buf = visual_end[1]
    if (start_buf == 0 or start_buf == bufnr) and (end_buf == 0 or end_buf == bufnr) then
      local v_start_line, v_start_col, v_end_line, v_end_col = ordered_positions(visual_start, visual_end)
      if v_start_line == start_line and v_end_line == end_line then
        start_col = v_start_col
        end_col = v_end_col
        selection_mode = "char"
        code = slice_visual_text(vim.deepcopy(lines), start_col, end_col)
      end
    end
  end

  local file = M.buf_file(bufnr)

  return {
    bufnr = bufnr,
    file = file,
    relfile = M.rel_file(file),
    start_line = start_line,
    end_line = end_line,
    start_col = start_col,
    end_col = end_col,
    selection_mode = selection_mode,
    code = code,
  }
end

function M.location(annotation)
  local range
  if annotation.start_line == annotation.end_line then
    range = tostring(annotation.start_line)
  else
    range = string.format("%d-%d", annotation.start_line, annotation.end_line)
  end

  if annotation.start_col and annotation.end_col then
    range = string.format("%s:%d-%d", range, annotation.start_col, annotation.end_col)
  end

  return string.format("%s:%s", annotation.relfile or M.rel_file(annotation.file or ""), range)
end

function M.read_annotation_code(annotation)
  if not annotation.file or annotation.file == "" or vim.fn.filereadable(annotation.file) ~= 1 then
    return nil
  end

  local ok, file_lines = pcall(vim.fn.readfile, annotation.file)
  if not ok or type(file_lines) ~= "table" then
    return nil
  end

  if annotation.start_line < 1 or annotation.end_line > #file_lines then
    return nil
  end

  local lines = {}
  for line = annotation.start_line, annotation.end_line do
    table.insert(lines, file_lines[line])
  end

  if annotation.start_col and annotation.end_col then
    return slice_visual_text(lines, annotation.start_col, annotation.end_col)
  end

  return table.concat(lines, "\n")
end

function M.is_stale(annotation)
  local current = M.read_annotation_code(annotation)
  if current == nil then
    return true
  end
  return current ~= (annotation.code or "")
end

function M.sort_annotations(annotations)
  table.sort(annotations, function(a, b)
    if (a.file or "") ~= (b.file or "") then
      return (a.file or "") < (b.file or "")
    end
    if (a.start_line or 0) ~= (b.start_line or 0) then
      return (a.start_line or 0) < (b.start_line or 0)
    end
    return (a.id or "") < (b.id or "")
  end)
  return annotations
end

function M.first_comment_line(comment)
  for line in string.gmatch(comment or "", "([^\n]+)") do
    local trimmed = M.trim(line)
    if trimmed ~= "" then
      return trimmed
    end
  end
  return "(empty comment)"
end

return M
