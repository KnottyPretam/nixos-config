return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    opts = {
      ensure_installed = { "lua_ls", "clangd", "harper_ls" },
      automatic_enable = false,
    },
  },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      vim.lsp.config("lua_ls", {
        capabilities = capabilities,
      })

      vim.lsp.config("clangd", {
        capabilities = capabilities,
        cmd = {
          "clangd",
          "--background-index",
          "--clang-tidy",
          "--header-insertion=iwyu",
          "--all-scopes-completion",
          "--limit-references=0",
        },
      })

      -- Harper is a grammar checker. Left at defaults it puts ~140 diagnostics on
      -- a single wiki page: SentenceCapitalization fires on every markdown list
      -- item, LongSentences on every nav strip. Keep the spell check, drop the
      -- prose-style linters, and report at HINT so it underlines rather than
      -- filling the sign column.
      vim.lsp.config("harper_ls", {
        capabilities = capabilities,
        settings = {
          ["harper-ls"] = {
            diagnosticSeverity = "hint",
            -- The vault is written in British English (334 British spellings to
            -- 80 American); harper defaults to American and flags every one.
            dialect = "British",
            linters = {
              SentenceCapitalization = false,
              OxfordComma = false,
              LongSentences = false,
              PhrasalVerbAsCompoundNoun = false,
              SpellCheck = true,
            },
            markdown = { IgnoreLinkTitle = true },
            userDictPath = vim.fn.expand("~/.config/nvim/harper-dict.txt"),
          },
        },
      })

      vim.lsp.enable("lua_ls")
      vim.lsp.enable("clangd")
      vim.lsp.enable("harper_ls")

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf }

          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set('n', '<leader>gk', vim.lsp.buf.signature_help, opts)
          vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>ga", vim.lsp.buf.code_action, opts)
          vim.keymap.set('n', '<leader>gs', vim.lsp.buf.document_symbol, opts)
          vim.keymap.set("n", "<leader>gf", function()
            vim.lsp.buf.format({ async = true })
          end, opts)

          vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, opts)
        --  vim.api.nvim_set_keymap('i', '<C-Space>', '<C-x><C-o>', { noremap = true, silent = true })

          
        end,
      })
    end,
  },
}
