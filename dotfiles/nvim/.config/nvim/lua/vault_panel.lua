local M = {}

local state = {
  win = nil,
  buf = nil,
}

local config = {
  vault  = vim.fn.expand("${HOME}/obsidian_vaults/tiberius"),  -- <-- your vault path
  index  = "index.md",
  height = 15,
}

local function panel_is_open()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function ensure_index_exists()
  local path = config.vault .. "/" .. config.index
  if vim.fn.filereadable(path) == 0 then
    vim.fn.mkdir(config.vault, "p")
    vim.fn.writefile({ "# Vault Index", "", "- [[" }, path)
  end
  return path
end

local function open_panel()
  local restore_buf = state.buf
  local fresh_path  = nil
  if not restore_buf or not vim.api.nvim_buf_is_valid(restore_buf) then
    fresh_path = ensure_index_exists()
  end

  -- Top horizontal split, full width
  vim.cmd("topleft split")
  vim.cmd("resize " .. config.height)
  state.win = vim.api.nvim_get_current_win()

  if fresh_path then
    vim.cmd("edit " .. vim.fn.fnameescape(fresh_path))
    state.buf = vim.api.nvim_get_current_buf()
  else
    vim.api.nvim_win_set_buf(state.win, restore_buf)
  end

  -- Panel polish
  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].winfixheight   = true

  -- `q` closes the panel from inside it
  vim.keymap.set("n", "q", function() M.toggle() end,
    { buffer = true, desc = "Close vault panel" })

  -- Focus the new panel (split lands you here, but be explicit)
  vim.api.nvim_set_current_win(state.win)
end

local function close_panel()
  if panel_is_open() then
    state.buf = vim.api.nvim_win_get_buf(state.win)
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

function M.toggle()
  if panel_is_open() then
    if vim.api.nvim_get_current_win() == state.win then
      close_panel()              -- already focused → close
    else
      vim.api.nvim_set_current_win(state.win)  -- open but unfocused → jump in
    end
  else
    open_panel()                 -- closed → open + focus
  end
end

function M.home()
  if not panel_is_open() then open_panel() end
  vim.api.nvim_set_current_win(state.win)
  vim.cmd("edit " .. vim.fn.fnameescape(config.vault .. "/" .. config.index))
  state.buf = vim.api.nvim_get_current_buf()
end

return M
