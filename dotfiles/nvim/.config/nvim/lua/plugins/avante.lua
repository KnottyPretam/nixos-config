-- Codex (ChatGPT plan) credentials come from the Codex CLI's auth.json.
-- The access token rotates every few hours and only `codex` itself refreshes
-- it, so it is re-read per request via api_key_name = "cmd:...". The account
-- id is stable, so it is read once here at startup.
local codex_auth_path = vim.fn.expand("~/.codex/auth.json")

local function codex_account_id()
  local ok, lines = pcall(vim.fn.readfile, codex_auth_path)
  if not ok or type(lines) ~= "table" then return "" end
  local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok2 or type(data) ~= "table" then return "" end
  local tokens = type(data.tokens) == "table" and data.tokens or {}
  return tokens.account_id or data.account_id or ""
end

-- Codex sends a stable per-process session id.
local codex_session_id = vim.fn.trim(vim.fn.system("uuidgen"))

return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  version = false,
  build = "make",

  -- Explicit lazy.nvim keymap for the Avante panel.
  -- I’m using <leader>at to match Avante’s default “Avante toggle” mapping.
  keys = {
    { "<leader>at", "<cmd>AvanteToggle<CR>", desc = "Avante: toggle panel" },
    { "<leader>as", "<cmd>AvanteStop<CR>", desc = "Avante: stop generation" },
    { "<leader>ac", "<cmd>AvanteClear<CR>", desc = "Avante: clear session" },

    -- If you truly want just <leader>a, use this instead and remove the line above:
    -- { "<leader>a", "<cmd>AvanteToggle<CR>", desc = "Avante: toggle panel" },
  },

  opts = {
    mode = "agentic",

    -- Default: Codex gpt-5.6-sol on the ChatGPT plan.
    provider = "codex",

    -- Traditional API providers
    providers = {
      -- Codex on your ChatGPT plan. NOTE: chatgpt.com/backend-api/codex is the
      -- Codex CLI's private backend, not a public API -- the request shape and
      -- these headers are reverse-engineered and may break without notice.
      -- If auth fails, run `codex` once to refresh the token, then retry.
      codex = {
        __inherited_from = "openai",
        endpoint = "https://chatgpt.com/backend-api/codex",
        model = "gpt-5.6-sol",
        timeout = 60000,
        -- Codex speaks the Responses API, not /chat/completions.
        use_response_api = true,
        api_key_name = [[cmd:python3 -c "import json,sys;d=json.load(open('/home/pchoudhury/.codex/auth.json'));t=d.get('tokens') or {};sys.stdout.write(t.get('access_token') or d.get('OPENAI_API_KEY') or '')"]],
        extra_headers = {
          ["chatgpt-account-id"] = codex_account_id(),
          ["OpenAI-Beta"] = "responses=experimental",
          ["originator"] = "codex_cli_rs",
          ["session_id"] = codex_session_id,
        },
        extra_request_body = {
          -- avante rewrites reasoning_effort -> reasoning.effort for the
          -- Responses API. "minimal" = answer immediately, no deliberation.
          reasoning_effort = "minimal",
          store = false,
        },
      },
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-haiku-4-5",
        timeout = 60000,
        api_key_name = "ANTHROPIC_API_KEY",
        -- Avante deep-merges its default extra_request_body
        -- ({ temperature = 0.75, max_tokens = 64000 }) into this block; 64000 is
        -- well past what a quick answer needs. temperature is stripped
        -- automatically for claude-haiku-[4-9].
        extra_request_body = {
          max_tokens = 8192,
        },
      },
      ollama = {
        endpoint = "http://127.0.0.1:11434",  -- no /v1
        model = "gpt-oss:20b",
        timeout = 60000,
        is_env_set = ollama_alive,
        extra_request_body = {
          options = {
            temperature = 0.75,
            num_ctx = 16384,
            keep_alive = "5m",
          },
        },
      },
      ["ollama-gemma"] = {
        __inherited_from = "ollama",
        model = "gemma4:26b",
      },
    },

    mappings = {
      toggle = {
        default = "<leader>at",
      },
    },
  },

  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",

    -- optional selectors/completion
    "echasnovski/mini.pick",
    "echasnovski/mini.diff",
    "nvim-telescope/telescope.nvim",
    "hrsh7th/nvim-cmp",
    "ibhagwan/fzf-lua",
    "nvim-tree/nvim-web-devicons",

    -- Not needed for Codex. Keep it only if you use Copilot elsewhere.
    -- "zbirenbaum/copilot.lua",

    {
      -- support for image pasting
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          use_absolute_path = true,
        },
      },
    },

    {
      "MeanderingProgrammer/render-markdown.nvim",
      opts = {
        file_types = { "markdown" },
        -- No LaTeX in these notes, and no latex2text/utftex installed to render
        -- it; leaving it on is three health warnings for nothing.
        latex = { enabled = false },
      },
      ft = { "markdown" },
    },
  },
}


-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
