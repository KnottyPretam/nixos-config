-- diff-vim.lua
-- Lazy.nvim spec for diffview.nvim with <leader>d* keymaps.
-- Drop this file into ~/.config/nvim/lua/plugins/ (LazyVim layout)
-- or `require` it from your lazy setup.

return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },

  -- Lazy-load on these commands and keys
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
    "DiffviewRefresh",
    "DiffviewFileHistory",
  },

  keys = {
    -- Core: open / close / toggle
    { "<leader>do", "<cmd>DiffviewOpen<cr>",                  desc = "Diffview: open (working tree vs HEAD)" },
    { "<leader>dc", "<cmd>DiffviewClose<cr>",                 desc = "Diffview: close" },
    { "<leader>dt", "<cmd>DiffviewToggleFiles<cr>",           desc = "Diffview: toggle file panel" },
    { "<leader>df", "<cmd>DiffviewFocusFiles<cr>",            desc = "Diffview: focus file panel" },
    { "<leader>dr", "<cmd>DiffviewRefresh<cr>",               desc = "Diffview: refresh" },

    -- Common revision ranges
    { "<leader>dm", "<cmd>DiffviewOpen origin/dev...HEAD<cr>", desc = "Diffview: vs origin/main" },
    { "<leader>dM", "<cmd>DiffviewOpen origin/master...HEAD<cr>", desc = "Diffview: vs origin/master" },
    { "<leader>dp", "<cmd>DiffviewOpen HEAD~1<cr>",           desc = "Diffview: vs previous commit" },

    -- File history
    { "<leader>dh", "<cmd>DiffviewFileHistory<cr>",           desc = "Diffview: repo history" },
    { "<leader>dH", "<cmd>DiffviewFileHistory %<cr>",         desc = "Diffview: current file history" },
    {
      "<leader>dl",
      function()
        -- History for the visually selected lines
        vim.cmd("'<,'>DiffviewFileHistory")
      end,
      mode = "v",
      desc = "Diffview: selected lines history",
    },
  },

  opts = {
    enhanced_diff_hl = true,           -- better diff highlight groups
    use_icons = true,                  -- requires a nerd font
    show_help_hints = true,
    watch_index = true,                -- auto-refresh on index changes

    view = {
      -- Force side-by-side everywhere (this is what you asked for)
      default        = { layout = "diff2_horizontal", winbar_info = false },
      merge_tool     = { layout = "diff3_horizontal", disable_diagnostics = true },
      file_history   = { layout = "diff2_horizontal", winbar_info = false },
    },

    file_panel = {
      listing_style = "tree",          -- "list" or "tree"
      tree_options = {
        flatten_dirs = true,
        folder_statuses = "only_folded",
      },
      win_config = {
        position = "left",
        width = 35,
      },
    },

    -- In-buffer keymaps while inside a diffview tab
    keymaps = {
      view = {
        { "n", "<leader>dq", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" } },
        { "n", "]x",         function() require("diffview.actions").next_conflict() end, { desc = "Next conflict" } },
        { "n", "[x",         function() require("diffview.actions").prev_conflict() end, { desc = "Prev conflict" } },
      },
      file_panel = {
        { "n", "j",  function() require("diffview.actions").next_entry() end,         { desc = "Next file" } },
        { "n", "k",  function() require("diffview.actions").prev_entry() end,         { desc = "Prev file" } },
        { "n", "<cr>", function() require("diffview.actions").select_entry() end,     { desc = "Open file diff" } },
        { "n", "s",  function() require("diffview.actions").toggle_stage_entry() end, { desc = "Stage / unstage" } },
        { "n", "R",  function() require("diffview.actions").refresh_files() end,      { desc = "Refresh" } },
      },
    },
  },
}
