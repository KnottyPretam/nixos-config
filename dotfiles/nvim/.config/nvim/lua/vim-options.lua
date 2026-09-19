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
