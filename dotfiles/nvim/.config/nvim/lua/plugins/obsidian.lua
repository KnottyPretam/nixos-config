-- Vault path comes from $HOME_VAULT - set it in nixos-config/env.nix.
local vault = vim.env.HOME_VAULT

return {
  "obsidian-nvim/obsidian.nvim",
  version = "*",                    -- pin to latest release
  -- Unset means nvim was not started from a Home Manager session; say so
  -- rather than failing inside the plugin.
  cond = function()
    if not vault or vault == "" then
      vim.notify("obsidian.nvim disabled: $HOME_VAULT is not set (nixos-config/env.nix)",
        vim.log.levels.WARN)
      return false
    end
    return true
  end,
  lazy = true,
  ft = "markdown",                  -- or use 'event' to load only inside the vault
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim", -- or fzf-lua / mini.pick
  },
  ---@module 'obsidian'
  ---@type obsidian.config
  opts = {
    legacy_commands = false,
    workspaces = {
      {
        name = vim.fn.fnamemodify(vault or "", ":t"),  -- the vault folder's name
        path = vault,
      },
    },
    completion = {
      min_chars = 2,
    },
    picker = { name = "telescope.nvim" },
  },
}
