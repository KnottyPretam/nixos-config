----------------------------------------------------
return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- `master` does not support Neovim 0.12: its markdown injections query
    -- shadows Neovim's own and calls set-lang-from-info-string!, which reads a
    -- query match as a single node. On 0.12 a match is a list of nodes, so any
    -- language-tagged code fence throws "attempt to call method 'range'" from
    -- the highlighter's decoration provider, on every redraw. `main` ships
    -- neither that query nor that directive.
    branch = "main",
    lazy = false,
    build = ":TSUpdate",

    config = function()
      require("nvim-treesitter").install({
        "python",
        "bash",
        "c",
        "cpp",
        "html",
        "css",
        "scss",
        "javascript",
        "typescript",
        "json",
        "lua",
        "vim",
        "vimdoc",
        "query",
        "markdown",
        "markdown_inline",
        "yaml",
      })

      -- On `main`, highlighting and indent are opt-in per buffer.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if not pcall(vim.treesitter.start, args.buf) then
            return
          end
          local lang = vim.treesitter.language.get_lang(args.match) or args.match
          if vim.treesitter.query.get(lang, "indents") then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
}
----------------------------------------------------
----------------------------------------------------
