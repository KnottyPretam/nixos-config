return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons", -- optional, but recommended
  },
  cmd = "Neotree",
  keys = {
    { "<leader>tt",  "<cmd>Neotree toggle <cr>", desc = "Toggle Neo-tree (reveal current file)" },
    { "<leader>to",  "<cmd>Neotree focus reveal<cr>",  desc = "Focus Neo-tree on current file" },
    { "<leader>tc",  "<cmd>Neotree close<cr>",         desc = "Close Neo-tree" },
    { "<leader>tr",  "<cmd>Neotree reveal<cr>",        desc = "Reveal current file" },
    { "<leader>tg", "<cmd>Neotree git_status<cr>",    desc = "Neo-tree git status" },
    { "<leader>tb",  "<cmd>Neotree buffers<cr>",       desc = "Neo-tree buffers" },
  },
--  opts = {
--    filesystem = {
--      follow_current_file = {
--        enabled = true,
--        leave_dirs_open = false,
--      },
--      use_libuv_file_watcher = true,
--    },
--  },
  lazy = false, -- neo-tree will lazily load itself
}
