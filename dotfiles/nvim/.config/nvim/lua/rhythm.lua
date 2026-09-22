-- The three-view shell of the rhythm note app.
--
-- Loaded ONLY by the overlay, via `nvim -c 'lua require("rhythm").open()'`.
-- Requiring this file does nothing on its own, so your everyday nvim is
-- untouched: no maps, no autocmds, no watchers until open() runs.
--
-- Views are TABPAGES tracked by handle, never by tabpagenr() -- diffview opens
-- its own tabpage and any index-based scheme would silently shift.
local M = {}

-- "" rather than nil: this file must be requirable even with nothing set,
-- so a broken environment surfaces in open() as a message, not a stack trace.
local VAULT = vim.env.RHYTHM_VAULT or vim.env.HOME_VAULT or ""
local KDIR, KFILE = VAULT .. "/kanban", "tiberius_kanban.md"
local ORDER = { "notepad", "kanban", "radar" }

M.tabs, M.bufs = {}, {}

local function sh(args)          -- fire and forget; never block the editor
  pcall(function() vim.system(args, { text = true }) end)
end

-- nvim_buf_set_lines throws on a nomodifiable buffer, so bracket every write.
-- `readonly` has to be cleared as well: leaving it set makes each write emit
-- "W10: Warning: Changing a readonly file", and three startup messages are
-- enough to trip the hit-enter prompt, which blocks nvim's main loop -- so the
-- overlay would open stuck, with SUPER+C silently doing nothing until you
-- pressed Enter. The watcher re-render would warn again on every board change.
local function render(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

local function kanban_lines()
  local p = KDIR .. "/" .. KFILE
  if vim.fn.filereadable(p) == 0 then return { "rhythm: no board at " .. p } end
  return vim.fn.readfile(p)
end

local function ro_tab(view, lines)
  vim.cmd.tabnew()
  -- Already buftype=nofile, bufhidden=hide, noswapfile, nobuflisted.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "rhythm://" .. view)
  vim.api.nvim_win_set_buf(0, buf)
  -- buftype=nofile blocks `:w` but NOT `:w <filename>`. This is what blocks
  -- that. Do NOT `return true` from the callback -- that deletes the autocmd.
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.notify("rhythm: " .. view .. " is read-only", vim.log.levels.WARN)
    end,
  })
  vim.keymap.set("n", "q", function() M.cycle(1) end,
    { buffer = buf, nowait = true, desc = "rhythm: next view" })
  render(buf, lines)
  vim.t.rhythm_view = view
  M.tabs[view], M.bufs[view] = vim.api.nvim_get_current_tabpage(), buf
end

function M.cycle(step)
  local cur, i = vim.t.rhythm_view, 0
  for n, v in ipairs(ORDER) do if v == cur then i = n end end
  -- i == 0 means a foreign tabpage (:DiffviewOpen, :tabnew) -- go home.
  local name = (i == 0) and "notepad" or ORDER[(i - 1 + step) % #ORDER + 1]
  local h = M.tabs[name]
  if h and vim.api.nvim_tabpage_is_valid(h) then
    vim.api.nvim_set_current_tabpage(h)
    -- Entering the board is the one moment a marker written in your ORDINARY
    -- nvim needs folding in. The dir watch below redraws when it lands.
    if name == "kanban" then sh({ "rhythm", "sync" }) end
  end
end

-- SUPER+C target. Both guards run in the same tick as the action: asking from
-- outside and then acting is two round trips with a gap in between, and the
-- act would ignore modal state.
function M.new_note()
  if vim.t.rhythm_view ~= "notepad" then return end
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "n" and mode ~= "i" then return end
  vim.schedule(function()
    -- `rhythm new` owns the naming and the O_EXCL allocation, so there is
    -- exactly one implementation of it.
    local r = vim.system({ "rhythm", "new" }, { text = true }):wait(2000)
    local path = r and r.code == 0 and vim.trim(r.stdout or "") or ""
    if path == "" then
      vim.notify("rhythm: could not create a note", vim.log.levels.ERROR)
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
  end)
end

function M.hide()
  sh({ "hyprctl", "dispatch", "togglespecialworkspace", "rhythm" })
end

function M.open()
  if VAULT == "" then
    vim.notify("rhythm: RHYTHM_VAULT is not set", vim.log.levels.ERROR)
    return
  end
  vim.fn.mkdir(VAULT .. "/unsorted", "p")
  vim.cmd.edit(vim.fn.fnameescape(
    VAULT .. "/unsorted/note_" .. os.date("%m-%d-%y") .. ".md"))
  vim.t.rhythm_view = "notepad"
  M.tabs.notepad = vim.api.nvim_get_current_tabpage()

  ro_tab("kanban", kanban_lines())
  ro_tab("radar", { "rhythm: activity radar -- phase 2" })
  vim.api.nvim_set_current_tabpage(M.tabs.notepad)

  -- Watch the DIRECTORY, not the file: `rhythm sync` writes temp + os.replace,
  -- and that rename orphans the file's inode, killing an inode-bound watch.
  -- The directory inode survives an atomic child replace, so this needs no
  -- re-arm. M.watch holds the reference -- an unreferenced uv handle is GC'd.
  local pending = false
  M.watch = vim.uv.new_fs_event()
  M.watch:start(KDIR, {}, function(err, fname)
    if err or fname ~= KFILE or pending then return end
    pending = true
    vim.defer_fn(function()
      pending = false
      render(M.bufs.kanban, kanban_lines())
    end, 50)
  end)

  -- Saving a note folds its markers into the board. The cursor line is passed
  -- so an id is never stamped into a sentence you are still typing.
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = VAULT .. "/unsorted/*.md",
    callback = function(a)
      sh({ "rhythm", "sync", a.file .. ":" .. vim.fn.line(".") })
    end,
  })

  -- Global, and in insert mode too. An UNMAPPED <M-Tab> does not no-op --
  -- nvim decomposes it into <Esc> then <Tab>, which would drop you out of
  -- insert and then insert a tab. <M-S-Tab> must be explicit for the same
  -- reason, or Alt+Shift+Tab becomes a stealth <Esc>.
  -- <C-\><C-n> rather than <Esc>: leaves insert without moving the cursor,
  -- and without it you land in insert on a nomodifiable buffer -> E21.
  vim.keymap.set({ "n", "v" }, "<M-Tab>", function() M.cycle(1) end,
    { desc = "rhythm: next view" })
  vim.keymap.set({ "n", "v" }, "<M-S-Tab>", function() M.cycle(-1) end,
    { desc = "rhythm: previous view" })
  vim.keymap.set("i", "<M-Tab>",
    [[<C-\><C-n><Cmd>lua require("rhythm").cycle(1)<CR>]])
  vim.keymap.set("i", "<M-S-Tab>",
    [[<C-\><C-n><Cmd>lua require("rhythm").cycle(-1)<CR>]])

  -- `ghostty -e` forces quit-after-last-window-closed, so a real :q kills the
  -- process and Hyprland then destroys the emptied special workspace. Hide
  -- instead. `:q!` and `:qa!` are left alone as the deliberate way out.
  vim.api.nvim_create_user_command("RhythmHide", function() M.hide() end, {})
  for _, c in ipairs({ "q", "qa", "wq", "x" }) do
    local rhs = (c == "wq" or c == "x") and "write <bar> RhythmHide" or "RhythmHide"
    vim.cmd(string.format(
      "cnoreabbrev <expr> %s (getcmdtype()==':' && getcmdline()==#'%s') ? '%s' : '%s'",
      c, c, rhs, c))
  end
end

return M
