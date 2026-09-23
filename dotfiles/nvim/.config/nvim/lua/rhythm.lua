-- The three-view shell of the rhythm note app, and the renderer for two of them.
--
-- Loaded ONLY by the overlay, via `nvim -c 'lua require("rhythm").open()'`.
-- Requiring this file does nothing on its own, so your everyday nvim is
-- untouched: no maps, no autocmds, no watchers until open() runs.
--
-- Views are TABPAGES tracked by handle, never by tabpagenr() -- diffview opens
-- its own tabpage and any index-based scheme would silently shift.
--
-- The board and radar are DRAWN, not dumped: `rhythm board` emits JSON and this
-- file lays it out. The card grammar lives in board.py and is deliberately not
-- reimplemented here -- a second parser that drifts from sync is a silent bug.
local M = {}

local VAULT = vim.env.RHYTHM_VAULT or vim.env.HOME_VAULT or ""
local KDIR, KFILE = VAULT .. "/kanban", "tiberius_kanban.md"
local ORDER = { "notepad", "activity", "project", "radar" }

-- The Alt-Tab rotation, deliberately NOT ORDER. The radar is a hardcoded
-- placeholder until its backend lands, so it is built and reachable but kept
-- out of the cycle: landing on a stub every third press is friction for no
-- information, and it puts the project board one press from the activity one.
-- <M-r> jumps to the radar; add it back here when it has real data.
local CYCLE = { "notepad", "activity", "project" }
local BOARDS = { activity = true, project = true }
local NS = vim.api.nvim_create_namespace("rhythm")

local MINW, GAP = 24, 2              -- minimum readable TEXT width; gutter between lanes
local PAD = 4                        -- a tile spends 2 cells on borders and 2 on padding
local REFRESH_MS = 30 * 60 * 1000    -- belt-and-braces refresh; the watcher does the rest

M.tabs, M.bufs, M.off, M.cards, M.data, M.gen = {}, {}, {}, {}, {}, {}
-- Selection. `sel` is a card ID, never a row: the board is refetched on every
-- sync by the directory watcher, and an index would slide under the selection
-- whenever a card was added above it. `col` is the ABSOLUTE column index, so it
-- survives lane scrolling, and `idx` is the depth within that column, which is
-- what the selection falls back to when its card disappears (you removed it).
M.sel, M.selcol, M.selidx, M.lanes = {}, {}, {}, {}

-- Foreground-only, always. catppuccin runs transparent_background and ghostty
-- has background-opacity=0.7 with background-opacity-cells unset, so any cell
-- given a `bg` renders 100% OPAQUE -- a tinted card would be a hard block.
local function hl()
  local function link(n, t) vim.api.nvim_set_hl(0, n, { link = t }) end
  link("RhythmTitle", "Title")
  link("RhythmRule", "WinSeparator")
  link("RhythmDim", "NonText")
  link("RhythmMeta", "Dimmed")
  link("RhythmOn", "Title")
  link("RhythmOff", "NonText")
  -- RenderMarkdownH1..H6 are plain { fg = rainbow<i> } and exist unconditionally
  -- because catppuccin's auto_integrations defines them whether or not the
  -- plugin loads. Seven lanes, six ramp colours, so Special takes the seventh.
  for i = 1, 6 do link("RhythmAccent" .. i, "RenderMarkdownH" .. i) end
  link("RhythmAccent7", "Special")
  -- Activity colours for the project board's card borders. Linked to the
  -- theme's own diagnostic groups rather than hardcoded hex, so they follow the
  -- colorscheme; under catppuccin these resolve to #f38ba8 / #a6e3a1 / #f9e2af.
  -- All three are foreground-only, which the opacity note above requires.
  link("RhythmActive", "DiagnosticError")    -- red
  link("RhythmMonitor", "DiagnosticOk")      -- green
  link("RhythmRoute", "DiagnosticWarn")      -- yellow
  -- Backlog is deliberately absent: "no colour" is the fourth state.
  link("RhythmSel", "CursorLineNr")
end

-- Activity -> border highlight. A missing entry (backlog, or no activity at
-- all) means the card keeps the default rule colour.
local TINT = {
  active = "RhythmActive",
  monitor = "RhythmMonitor",
  route = "RhythmRoute",
}

---------------------------------------------------------------------------
-- display-cell helpers
---------------------------------------------------------------------------

-- ASCII byte class ONLY: every byte here is <0x80 so it can never match inside
-- a UTF-8 sequence. A \u{...} range in a Lua pattern degrades to a BYTE range
-- and shreds valid text. set_lines also hard-errors on an embedded newline.
local function clean(s)
  return (tostring(s):gsub("[%z\1-\31\127]", " "))
end

-- Pad or truncate to exactly `w` display cells. nvim_strwidth is the only
-- correct width authority once the control bytes are gone; #s is bytes, and
-- byte-slicing a grapheme can make the result WIDER than the original.
local function fit(s, w)
  if w < 1 then return "" end
  s = clean(s)
  local sw = vim.api.nvim_strwidth(s)
  if sw <= w then return s .. string.rep(" ", w - sw) end
  local out, used = {}, 0
  for i = 0, vim.fn.strchars(s, 1) - 1 do
    local g = vim.fn.strcharpart(s, i, 1, 1)   -- skipcc=1 => whole graphemes
    local gw = vim.api.nvim_strwidth(g)
    if used + gw > w - 1 then break end        -- reserve 1 cell for the ellipsis
    out[#out + 1], used = g, used + gw
  end
  return table.concat(out) .. "…" .. string.rep(" ", w - used - 1)
end

-- Greedy wrap to `w` cells. A single word longer than the lane is hard-cut by
-- fit() rather than overflowing.
local function wrap(s, w)
  local out, line = {}, ""
  for word in clean(s):gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if vim.api.nvim_strwidth(try) <= w then
      line = try
    else
      if line ~= "" then out[#out + 1] = line end
      line = word
    end
  end
  if line ~= "" then out[#out + 1] = line end
  return #out > 0 and out or { "" }
end

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------

-- Lanes are sized from the LIVE window width. 142 -> 4 lanes of 29 cells,
-- 92 -> 3 of 24.
local function geometry(width, ncols)
  local usable = width - 2                     -- 1-cell inset: rounding clips the corners
  local lanes = math.floor((usable + GAP) / (MINW + PAD + GAP))
  lanes = math.max(1, math.min(lanes, math.max(ncols, 1)))
  local tw = math.floor((usable - (lanes - 1) * GAP) / lanes) - PAD
  return lanes, math.max(MINW, tw)
end

-- Accumulate a line from {text, hl_group} segments, recording BYTE offsets --
-- extmark columns are bytes, not cells, and box-drawing glyphs are 3 bytes each.
local function push(st, segs)
  local parts, col = {}, 0
  for _, s in ipairs(segs) do
    local t = s[1]
    if s[2] then
      st.marks[#st.marks + 1] = { #st.rows, col, col + #t, s[2] }
    end
    parts[#parts + 1] = t
    col = col + #t
  end
  -- Every row is padded to the exact window width HERE, in one place, rather
  -- than each call site remembering to add the slack. fit() also truncates, so
  -- an over-long row shows an ellipsis instead of silently shearing the grid.
  -- Padding only appends spaces, so the byte offsets recorded above stay valid.
  st.rows[#st.rows + 1] = fit(table.concat(parts), st.w)
end

--- Draw `data` into a list of lines plus extmarks plus a card-region table.
local function compose(data, width, height, off, sel)
  local st = { rows = {}, marks = {}, cards = {}, w = width, selfound = false }
  local cols = data.columns or {}
  local lanes, tw = geometry(width, #cols)
  off = math.max(0, math.min(off or 0, math.max(0, #cols - lanes)))

  local shown = {}
  for i = off + 1, math.min(off + lanes, #cols) do shown[#shown + 1] = cols[i] end

  local lane = tw + PAD                        -- full tile width
  local gutter = string.rep(" ", GAP)
  -- title bar: name on the left, scroll position on the right
  local dots = {}
  for i = 1, #cols do dots[i] = (i > off and i <= off + lanes) and "●" or "○" end
  local pos = #cols > lanes
      and (table.concat(dots) .. "  " .. (off + 1) .. "-" .. math.min(off + lanes, #cols)
           .. " of " .. #cols .. "  h/l")
      or (#cols .. " columns")
  local tleft = " ▌ " .. clean(data.title or "")
  push(st, {
    { fit(tleft, width - vim.api.nvim_strwidth(pos) - 2), "RhythmTitle" },
    { pos, "RhythmDim" }, { "  " },
  })
  push(st, { { "" } })

  -- headers, then a rule whose weight says whether the lane has anything in it
  local head, rule = { { " " } }, { { " " } }
  for i, c in ipairs(shown) do
    local n = #(c.entries or {})
    local a = "RhythmAccent" .. ((tonumber(c.accent) or 0) % 7 + 1)
    local cnt = tostring(n)
    head[#head + 1] = { fit(string.upper(clean(c.title or "")), lane - #cnt - 1), a }
    head[#head + 1] = { cnt .. " ", n > 0 and a or "RhythmDim" }
    rule[#rule + 1] = { string.rep(n > 0 and "━" or "─", lane), n > 0 and a or "RhythmRule" }
    if i < #shown then head[#head + 1] = { gutter }; rule[#rule + 1] = { gutter } end
  end
  push(st, head)
  push(st, rule)
  push(st, { { "" } })

  -- Build each lane's rows independently, then transpose. A tile is
  -- top / text.. / bottom, with one blank row between tiles.
  local body = height - #st.rows - 1           -- reserve the footer
  local grids = {}
  for li, c in ipairs(shown) do
    local g, used, over = {}, 0, 0
    local entries = c.entries or {}
    if #entries == 0 then
      g[1] = { { fit("  empty", lane), "RhythmDim" } }
    end
    for ei, e in ipairs(entries) do
      local lines = wrap(e.text or "", tw)
      -- the radar's age string rides the last text line, right-aligned, and
      -- takes a line of its own only when it cannot keep a 2-cell gap
      local meta, mw = clean(e.meta or ""), 0
      if meta ~= "" then
        mw = vim.api.nvim_strwidth(meta)
        local last = lines[#lines]
        if vim.api.nvim_strwidth(last) + mw + 2 > tw then lines[#lines + 1] = "" end
      end
      local cost = #lines + 2 + (used > 0 and 1 or 0)
      if used + cost > body - 1 then over = #entries - ei + 1 break end
      if used > 0 then g[#g + 1] = { { string.rep(" ", lane) } }; used = used + 1 end
      local dim = e.dim and "RhythmDim" or nil
      -- Border colour, in priority order: the selection (the one thing you
      -- must never lose track of), then the activity tint the payload asked
      -- for, then done-ness, then the plain rule.
      local picked = sel and e.id ~= "" and e.id == sel
      local edge = (picked and "RhythmSel") or TINT[e.tint or ""] or dim or "RhythmRule"
      if picked then st.selfound = true end
      g[#g + 1] = { { "╭" .. string.rep("─", tw + 2) .. "╮", edge } }
      local first = #g
      for i, t in ipairs(lines) do
        local m = (i == #lines) and meta or ""
        g[#g + 1] = { { "│ ", edge }, { fit(t, tw - (m == "" and 0 or mw)), dim },
                      { m, "RhythmMeta" }, { " │", edge } }
      end
      g[#g + 1] = { { "╰" .. string.rep("─", tw + 2) .. "╯", edge } }
      used = used + cost - (used > 0 and 1 or 0)
      -- Where this card sits. `col` is the ABSOLUTE column index (lanes are
      -- relative to the current scroll offset), which is what navigation and
      -- the selection are keyed on.
      st.cards[#st.cards + 1] = {
        lane = li, col = off + li, depth = ei,
        r1 = first, r2 = #g, id = e.id or "", text = e.text or "",
      }
    end
    if over > 0 then g[#g + 1] = { { fit("  +" .. over .. " more", lane), "RhythmDim" } } end
    grids[li] = g
  end

  local deepest = 0
  for _, g in ipairs(grids) do deepest = math.max(deepest, #g) end
  local top = #st.rows                          -- buffer row where the grid starts

  for r = 1, math.max(deepest, 1) do
    if #st.rows - top >= body then break end
    local segs = { { " " } }
    for li = 1, #shown do
      local cell = grids[li][r]
      if cell then
        for _, part in ipairs(cell) do segs[#segs + 1] = part end
      else
        segs[#segs + 1] = { string.rep(" ", lane) }
      end
      if li < #shown then segs[#segs + 1] = { gutter } end
    end
    push(st, segs)
  end

  -- translate per-lane grid rows into absolute buffer rows and cell columns
  for _, cd in ipairs(st.cards) do
    cd.row1 = top + cd.r1 - 1
    cd.row2 = top + cd.r2 - 1
    cd.c1 = 1 + (cd.lane - 1) * (lane + GAP) + 1
    cd.c2 = cd.c1 + lane - 1
  end

  while #st.rows < height - 1 do push(st, { { "" } }) end
  local right = #st.cards .. " shown  "
  local hint = width < 80 and "  jk card  hl column  x remove  q next"
      or "  j k  card     h l  column     x  remove card     q  next view"
  push(st, {
    { fit(hint, width - vim.api.nvim_strwidth(right)), "RhythmDim" },
    { right, "RhythmDim" },
  })

  st.off = off
  st.lanes = lanes
  st.ncols = #cols
  return st
end

---------------------------------------------------------------------------
-- painting
---------------------------------------------------------------------------

local function win_of(view)
  local b = M.bufs[view]
  return b and vim.fn.win_findbuf(b)[1] or nil
end

local function paint(view)
  local buf, win = M.bufs[view], win_of(view)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not win then return end
  local data = M.data[view]
  if not data then return end

  local w = vim.api.nvim_win_get_width(win)
  local h = vim.api.nvim_win_get_height(win)
  local st = compose(data, w, h, M.off[view], M.sel[view])

  -- The selected card is gone (you removed it, or a sync moved it off this
  -- board). Fall back to the same DEPTH in the same column, which is where the
  -- eye already is, and draw once more so the new selection is visible. Only
  -- the rare case pays for the second compose.
  if not st.selfound and #st.cards > 0 then
    local col, want = M.selcol[view] or 1, M.selidx[view] or 1
    local list = {}
    for _, c in ipairs(st.cards) do if c.col == col then list[#list + 1] = c end end
    if #list == 0 then                       -- that column emptied: take any
      list, M.selcol[view] = st.cards, st.cards[1].col
    end
    local pick = list[math.max(1, math.min(want, #list))]
    M.sel[view], M.selidx[view] = pick.id, math.max(1, math.min(want, #list))
    st = compose(data, w, h, M.off[view], M.sel[view])
  end

  M.off[view] = st.off                       -- compose clamps; write it back
  M.cards[view] = st.cards
  M.lanes[view] = st.lanes

  -- `readonly` must be cleared as well as `modifiable`: leaving it set makes
  -- each write emit W10, and enough messages trip the hit-enter prompt, which
  -- blocks the main loop.
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, st.rows)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, m in ipairs(st.marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

-- Exposed: the resize autocmd, the refresh timer and the render test all
-- repaint a view without going through a fetch.
M.paint = paint

local function fetch(view)
  if view == "radar" then
    M.data.radar = {
      title = "RADAR",
      columns = {
        { title = "Now", accent = 4, entries = {} },
        { title = "Touched today", accent = 5, entries = {} },
        { title = "Recent", accent = 6,
          entries = { { text = "the radar backend is not built yet", meta = "", dim = true, id = "" } } },
      },
    }
    paint(view)
    return
  end
  M.gen[view] = (M.gen[view] or 0) + 1
  local mine = M.gen[view]
  -- One board per call: `view` is literally the CLI's argument, so the two
  -- boards stay two small payloads and the grouping stays in board.py.
  vim.system({ "rhythm", "board", view }, { text = true }, function(r)
    -- fast event context: decode here, everything else on the main loop
    local ok, decoded = pcall(vim.json.decode, r.stdout or "")
    vim.schedule(function()
      if mine ~= M.gen[view] then return end   -- a newer fetch already won
      if not ok or type(decoded) ~= "table" then
        local why = (r.stderr or ""):gsub("\n.*", "")
        M.data[view] = { title = "BOARD", columns = { { title = "unavailable", accent = 0,
          entries = { { text = why ~= "" and why or "rhythm board failed", dim = true, id = "" } } } } }
      else
        M.data[view] = decoded
      end
      paint(view)
    end)
  end)
end

---------------------------------------------------------------------------
-- views
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- selection and navigation
---------------------------------------------------------------------------

local function in_col(view, col)
  local out = {}
  for _, c in ipairs(M.cards[view] or {}) do
    if c.col == col then out[#out + 1] = c end
  end
  return out
end

local function current(view)
  for n, c in ipairs(in_col(view, M.selcol[view] or 1)) do
    if c.id == M.sel[view] then return n, c end
  end
  return nil, nil
end

--- j / k: the next card down or up, within the current column.
local function move_row(view, step)
  local list = in_col(view, M.selcol[view] or 1)
  if #list == 0 then return end
  local i = (current(view)) or 1
  i = math.max(1, math.min(i + step, #list))
  M.sel[view], M.selidx[view] = list[i].id, i
  paint(view)
end

--- h / l: the column to the left or right, holding roughly the same depth.
--- A column scrolled off-screen is scrolled INTO view first -- otherwise its
--- cards are not drawn, so there would be nothing to select.
local function move_col(view, step)
  local cols = ((M.data[view] or {}).columns) or {}
  if #cols == 0 then return end
  local want = M.selidx[view] or 1

  -- Step over EMPTY columns rather than landing on one: an empty lane has
  -- nothing to select, so stopping there would make the keypress look dead.
  -- Counts come from the payload, not from the drawn cards, so a column that
  -- is currently scrolled off-screen is still considered.
  local col = (M.selcol[view] or 1) + step
  while col >= 1 and col <= #cols and #(cols[col].entries or {}) == 0 do
    col = col + step
  end
  if col < 1 or col > #cols then return end    -- nothing further that way
  M.selcol[view] = col

  local lanes, off = M.lanes[view] or 1, M.off[view] or 0
  if col <= off then off = col - 1
  elseif col > off + lanes then off = col - lanes end
  M.off[view] = math.max(0, off)

  paint(view)                                  -- lays out the new lane strip
  local list = in_col(view, col)
  if #list > 0 then
    local i = math.max(1, math.min(want, #list))
    M.sel[view], M.selidx[view] = list[i].id, i
  end
  paint(view)                                  -- now show the selection
end

--- `x`: drop the selected card. Its id stays in the board's seen-set, which is
--- what makes sync ignore that marker in the note from now on.
local function remove_selected()
  local view = vim.t.rhythm_view
  local _, c = current(view)
  if not c then return end
  if c.id == "" then
    vim.notify("rhythm: that card has no id -- edit the board file to drop it",
      vim.log.levels.WARN)
    return
  end
  if vim.fn.confirm("Remove card?\n\n  " .. c.text, "&Yes\n&No", 2) ~= 1 then return end
  vim.system({ "rhythm", "remove", c.id }, { text = true }, vim.schedule_wrap(function()
    -- BOTH boards: the card was on each of them, so refreshing only this one
    -- would leave the other showing a card that no longer exists.
    M.refresh()
  end))
end

--- Refetch every board view. The card set is shared, so anything that changes
--- it changes both.
function M.refresh()
  for v in pairs(BOARDS) do fetch(v) end
end

local function ro_tab(view)
  vim.cmd.tabnew()
  -- Already buftype=nofile, bufhidden=hide, noswapfile, nobuflisted.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "rhythm://" .. view)
  vim.api.nvim_win_set_buf(0, buf)
  -- number and wrap are ON in this user's globals and both wreck a fixed grid.
  local w = vim.api.nvim_get_current_win()
  vim.wo[w].number         = false
  vim.wo[w].relativenumber = false
  vim.wo[w].signcolumn     = "no"
  vim.wo[w].foldcolumn     = "0"
  vim.wo[w].cursorline     = false
  vim.wo[w].wrap           = false
  vim.wo[w].list           = false
  vim.wo[w].fillchars      = "eob: "
  -- buftype=nofile blocks `:w` but NOT `:w <filename>`. This is what blocks it.
  -- Do NOT `return true` from the callback -- that deletes the autocmd.
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.notify("rhythm: " .. view .. " is read-only", vim.log.levels.WARN)
    end,
  })
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  map("q", function() M.cycle(1) end)
  map("j", function() move_row(view, 1) end)
  map("k", function() move_row(view, -1) end)
  map("<Down>", function() move_row(view, 1) end)
  map("<Up>", function() move_row(view, -1) end)
  map("h", function() move_col(view, -1) end)
  map("l", function() move_col(view, 1) end)
  map("<Left>", function() move_col(view, -1) end)
  map("<Right>", function() move_col(view, 1) end)
  map("g", function() move_row(view, -999) end)
  map("G", function() move_row(view, 999) end)
  map("x", remove_selected)
  map("r", function() fetch(view) end)
  vim.t.rhythm_view = view
  M.tabs[view], M.bufs[view], M.off[view] = vim.api.nvim_get_current_tabpage(), buf, 0
  M.selcol[view], M.selidx[view] = 1, 1
end

function M.tabline()
  local cur, out = vim.t.rhythm_view, {}
  local in_cycle = {}
  for _, v in ipairs(CYCLE) do in_cycle[v] = true end
  for _, v in ipairs(ORDER) do
    local on = v == cur
    -- a view outside the rotation keeps its slot but says so, so the tabline
    -- never implies Alt-Tab will reach it
    out[#out + 1] = ("%%#%s# %s %s "):format(on and "RhythmOn" or "RhythmOff",
      on and "●" or (in_cycle[v] and "○" or "·"), v)
  end
  return table.concat(out) .. "%#RhythmOff#%=alt-tab ⇄   alt-r radar  "
end

function M.goto_view(name)
  local h = M.tabs[name]
  if not (h and vim.api.nvim_tabpage_is_valid(h)) then return end
  vim.api.nvim_set_current_tabpage(h)
  if name ~= "notepad" then fetch(name) end
  vim.cmd.redrawtabline()
end

function M.cycle(step)
  local cur, i = vim.t.rhythm_view, 0
  for n, v in ipairs(CYCLE) do if v == cur then i = n end end
  -- i == 0 is any view outside the rotation -- a foreign tabpage
  -- (:DiffviewOpen, :tabnew) or the radar. Going home is right for all of them.
  M.goto_view((i == 0) and "notepad" or CYCLE[(i - 1 + step) % #CYCLE + 1])
end

-- SUPER+C target. Both guards run in the same tick as the action: asking from
-- outside and then acting is two round trips with a gap in between.
function M.new_note()
  if vim.t.rhythm_view ~= "notepad" then return end
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "n" and mode ~= "i" then return end
  vim.schedule(function()
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
  pcall(function()
    vim.system({ "hyprctl", "dispatch", "togglespecialworkspace", "rhythm" })
  end)
end

function M.open()
  if VAULT == "" then
    vim.notify("rhythm: RHYTHM_VAULT is not set", vim.log.levels.ERROR)
    return
  end
  hl()
  vim.fn.mkdir(VAULT .. "/unsorted", "p")
  vim.cmd.edit(vim.fn.fnameescape(
    VAULT .. "/unsorted/note_" .. os.date("%m-%d-%y") .. ".md"))
  vim.t.rhythm_view = "notepad"
  M.tabs.notepad = vim.api.nvim_get_current_tabpage()

  -- Created in ORDER, so Alt-Tab walks them in the order the tabline shows.
  ro_tab("activity")
  ro_tab("project")
  ro_tab("radar")
  vim.api.nvim_set_current_tabpage(M.tabs.notepad)
  M.refresh()
  fetch("radar")

  vim.o.showtabline = 2
  -- A global, not '%!v:lua.require("rhythm").tabline()': v:lua cannot chain a
  -- call off require() here. That form fails with E5101 + E117, and those two
  -- messages alone are enough to trip the hit-enter prompt, which blocks the
  -- main loop and leaves the overlay opening stuck.
  _G.RhythmTabline = function() return M.tabline() end
  vim.o.tabline = "%!v:lua.RhythmTabline()"

  -- Watch the DIRECTORY, not the file: `rhythm sync` writes temp + os.replace,
  -- and that rename orphans the file's inode, killing an inode-bound watch.
  -- M.watch holds the reference -- an unreferenced uv handle is GC'd.
  local pending = false
  M.watch = vim.uv.new_fs_event()
  M.watch:start(KDIR, {}, function(err, fname)
    if err or fname ~= KFILE or pending then return end
    pending = true
    -- Both boards: one file backs them both.
    vim.defer_fn(function() pending = false; M.refresh() end, 50)
  end)

  -- The board file has a watcher; the radar has no file to watch. This keeps
  -- both honest even if nothing touches them.
  M.timer = vim.uv.new_timer()
  M.timer:start(REFRESH_MS, REFRESH_MS, vim.schedule_wrap(function()
    M.refresh()
    fetch("radar")
  end))

  -- Saving a note folds its markers into the board. The cursor line is passed
  -- so an id is never stamped into a sentence you are still typing.
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = VAULT .. "/unsorted/*.md",
    callback = function(a)
      vim.system({ "rhythm", "sync", a.file .. ":" .. vim.fn.line(".") })
    end,
  })

  -- Only the on-screen view can be measured: nvim_win_get_width lies for a
  -- window in another tabpage. The others repaint when entered.
  vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
    callback = function()
      local v = vim.t.rhythm_view
      if v and v ~= "notepad" then paint(v) end
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
  -- The radar is out of the rotation, so it needs its own way in. Mapped in
  -- every mode for the same reason <M-Tab> is: an unmapped <M-r> does not
  -- no-op, nvim decomposes it into <Esc> then r, which in insert mode drops
  -- you out and starts a character-replace.
  vim.keymap.set({ "n", "v" }, "<M-r>", function() M.goto_view("radar") end,
    { desc = "rhythm: activity radar" })
  vim.keymap.set("i", "<M-r>",
    [[<C-\><C-n><Cmd>lua require("rhythm").goto_view("radar")<CR>]])

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
