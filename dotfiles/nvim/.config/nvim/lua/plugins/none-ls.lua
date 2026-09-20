return {
  "nvimtools/none-ls.nvim",
  config = function()
    local null_ls = require("null-ls")

    -- Every source here is declared in home.packages, so this works on any
    -- machine the flake builds. shellharden and erb_lint were dropped: neither
    -- is installed, and nothing in this config is Ruby.
    null_ls.setup({
      sources = {
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.formatting.prettier,
        null_ls.builtins.formatting.shfmt,
      },
    })

    vim.keymap.set("n", "<leader>gf", vim.lsp.buf.format, {})
  end,
}
