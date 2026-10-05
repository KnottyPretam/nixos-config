vim.cmd("set expandtab")
vim.cmd("set number")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.cmd("set wrap")
vim.g.mapleader = " "

vim.opt.swapfile = false

-- Navigate vim panes better
vim.keymap.set('n', '<c-k>', ':wincmd k<CR>')
vim.keymap.set('n', '<c-j>', ':wincmd j<CR>')
vim.keymap.set('n', '<c-h>', ':wincmd h<CR>')
vim.keymap.set('n', '<c-l>', ':wincmd l<CR>')

--vim.keymap.set('n', '<leader>vc', '<cmd>cclose<CR>')
vim.keymap.set('n', '<leader>vc', '<cmd>clo<CR>')
vim.keymap.set('n', '<leader>vh', '<cmd>nohlsearch<CR>')
vim.keymap.set('i', '<C-g>', '<C-x><C-o>', { noremap = true, silent = true })
vim.wo.number = true

-- <leader>0 : back to the ORIGINAL buffer - the first real file of this
-- session, no matter how far you have wandered since.
--
-- "First real file", not literally the first buffer: started bare, nvim sits
-- on an empty unnamed buffer (or a dashboard), and returning THERE would be
-- useless. buftype ~= "" also skips oil, neo-tree, avante, claude and
-- terminals, which are the buffers you most often jump away to.
local origin = { buf = nil, path = nil }

vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Remember the first real file buffer",
  callback = function(a)
    if vim.bo[a.buf].buftype ~= "" then return end
    local path = vim.api.nvim_buf_get_name(a.buf)
    if path == "" then return end
    origin.buf, origin.path = a.buf, path
    return true                       -- true deletes the autocmd: once only
  end,
})

vim.keymap.set("n", "<leader>0", function()
  -- Prefer the handle; fall back to the path, so the jump still works after
  -- the original was :bdelete'd.
  if origin.buf and vim.api.nvim_buf_is_valid(origin.buf) then
    vim.api.nvim_set_current_buf(origin.buf)
  elseif origin.path and vim.fn.filereadable(origin.path) == 1 then
    vim.cmd.edit(vim.fn.fnameescape(origin.path))
  else
    vim.notify("no original buffer yet", vim.log.levels.WARN)
  end
end, { desc = "Back to the original buffer" })

--obsidian key mappings
vim.keymap.set("n", "<leader>ov", function() require("vault_panel").toggle() end,
  { desc = "Toggle vault panel" })
vim.keymap.set("n", "<leader>oh", function() require("vault_panel").home() end,
  { desc = "Vault panel: jump to index" })

--remapping gf to create new file if it doesn't exist
vim.keymap.set("n", "gf", function()
  local target = vim.fn.expand("<cfile>")
  if target == "" then return end
  -- Resolve relative to current buffer's directory
  if not target:match("^[~/]") and not target:match("^%a+://") then
    target = vim.fn.expand("%:p:h") .. "/" .. target
  end
  vim.cmd("edit " .. vim.fn.fnameescape(target))
end, { desc = "gf with create-if-missing" })
