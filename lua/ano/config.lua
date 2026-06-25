local M = {}

local defaults = {
  state_dir = vim.fn.stdpath("data") .. "/ano",
  mirror_in_tmp = true,
  id_prefix = "Ano",
  default_markdown_path = ".local-review/review.md",
  include_resolved_in_export = false,
  default_keymaps = true,
  virtual_text = true,
}

local config = vim.deepcopy(defaults)

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get()
  return config
end

return M
