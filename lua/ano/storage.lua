local config = require("ano.config")
local util = require("ano.util")

local M = {}

local state

local function state_path()
  local cfg = config.get()
  vim.fn.mkdir(cfg.state_dir, "p")
  return string.format("%s/%s.json", cfg.state_dir, vim.fn.sha256(vim.fn.getcwd()))
end

local function empty_state()
  return {
    version = 1,
    project = vim.fn.getcwd(),
    next_id = 1,
    annotations = {},
  }
end

local function normalize(decoded)
  if type(decoded) ~= "table" then
    return empty_state()
  end

  decoded.version = decoded.version or 1
  decoded.project = decoded.project or vim.fn.getcwd()
  decoded.next_id = tonumber(decoded.next_id) or 1
  decoded.annotations = type(decoded.annotations) == "table" and decoded.annotations or {}

  return decoded
end

function M.load()
  if state then
    return state
  end

  local path = state_path()
  if vim.fn.filereadable(path) ~= 1 then
    state = empty_state()
    return state
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    state = empty_state()
    return state
  end

  local decoded_ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not decoded_ok then
    state = empty_state()
    return state
  end

  state = normalize(decoded)
  return state
end

function M.save()
  local current = M.load()
  current.project = vim.fn.getcwd()

  local path = state_path()
  util.ensure_parent(path)

  local ok, err = pcall(vim.fn.writefile, { vim.fn.json_encode(current) }, path)
  if not ok then
    util.notify("failed to write state: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.next_id()
  local current = M.load()
  local id = string.format("%s%d", config.get().id_prefix, current.next_id)
  current.next_id = current.next_id + 1
  return id
end

function M.all()
  return M.load().annotations
end

function M.add(annotation)
  table.insert(M.load().annotations, annotation)
  M.save()
  return annotation
end

function M.find(id)
  if not id or id == "" then
    return nil
  end

  for _, annotation in ipairs(M.all()) do
    if annotation.id == id then
      return annotation
    end
  end

  return nil
end

function M.delete(id)
  local annotations = M.all()
  for index, annotation in ipairs(annotations) do
    if annotation.id == id then
      table.remove(annotations, index)
      M.save()
      return annotation
    end
  end
  return nil
end

function M.clear_resolved()
  local annotations = M.all()
  local kept = {}
  local removed = 0

  for _, annotation in ipairs(annotations) do
    if annotation.status == "resolved" then
      removed = removed + 1
    else
      table.insert(kept, annotation)
    end
  end

  M.load().annotations = kept
  M.save()
  return removed
end

function M.clear_all()
  local removed = #M.all()
  M.load().annotations = {}
  M.save()
  return removed
end

return M
