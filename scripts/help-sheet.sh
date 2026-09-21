# Keyboard-shortcut cheatsheets, styled after Omarchy's keybindings menu.
#
# The look is one printf: the chord padded to exactly COLUMN characters, then a
# literal arrow, then the description. Every row pads identically, so the arrows
# form a vertical rule down the middle - that alignment IS the look.
#
# rofi is layer-shell, so it self-centres and takes keyboard focus with no
# Hyprland window rule. Do not add one; it would do nothing.

set -euo pipefail

COLUMN=35
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE="$RUNDIR/help-sheet.current"   # which sheet is showing (read by SUPER+Tab)
NEXT="$RUNDIR/help-sheet.next"       # SUPER+Tab writes the sheet to switch to
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/help-sheet"

# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

fmt() { awk -F'\t' -v c="$COLUMN" '$1 != "" { printf "%-*s \xe2\x86\x92 %s\n", c, $1, $2 }'; }

# ---------------------------------------------------------------------------
# Hyprland - from `hyprctl binds`, reading the bindd description field.
# Falls back to dispatcher+arg so an un-migrated bind still shows something.
# ---------------------------------------------------------------------------

render_hypr() {
  hyprctl binds -j \
    | jq -r '.[] | [ (.modmask|tostring), .key,
                     (if (.description // "") != "" then .description
                      else ((.dispatcher // "") + " " + (.arg // "")) end) ] | @tsv' \
    | awk -F'\t' '
        BEGIN {
          m[0]=""; m[1]="SHIFT"; m[4]="CTRL"; m[5]="SHIFT CTRL"; m[8]="ALT"
          m[9]="SHIFT ALT"; m[12]="CTRL ALT"; m[64]="SUPER"; m[65]="SUPER SHIFT"
          m[68]="SUPER CTRL"; m[72]="SUPER ALT"; m[76]="SUPER CTRL ALT"
        }
        {
          mod = ($1 in m) ? m[$1] : ("MOD" $1)
          chord = (mod == "") ? $2 : (mod " + " $2)
          gsub(/[ \t]+$/, "", $3)
          if ($3 != "") printf "%s\t%s\n", chord, $3
        }' \
    | sort -u | fmt
}

# ---------------------------------------------------------------------------
# tmux - diff a throwaway server against a bare one, so only YOUR bindings and
# your plugins' bindings show, not tmux's ~260 defaults. The plugin bindings
# (copycat, sessionist, resurrect) exist nowhere in home.nix and are the ones
# most worth a cheatsheet.
#
# -L uses a private socket and the server exits by itself once the command
# returns; it never touches a running session.
# ---------------------------------------------------------------------------

render_tmux() {
  conf="$HOME/.config/tmux/tmux.conf"
  defaults=$(tmux -f /dev/null -L helpsheet-bare list-keys 2>/dev/null | sed 's/  */ /g' | sort || true)
  if tmux has-session 2>/dev/null; then
    current=$(tmux list-keys 2>/dev/null | sed 's/  */ /g' | sort || true)
  else
    current=$(tmux -f "$conf" -L helpsheet list-keys 2>/dev/null | sed 's/  */ /g' | sort || true)
  fi

  comm -13 <(printf '%s\n' "$defaults") <(printf '%s\n' "$current") \
    | sed -E 's#/nix/store/[a-z0-9]+-tmuxplugin-([a-zA-Z0-9-]+)-[^/]*/[^ "]*#[\1]#g' \
    | awk '
        {
          table = ""; key = ""; cmd = ""
          for (i = 1; i <= NF; i++) {
            if ($i == "-T") { table = $(i+1); key = $(i+2)
                              for (j = i+3; j <= NF; j++) cmd = cmd (cmd=="" ? "" : " ") $j
                              break }
          }
          if (key == "") next
          if      (table == "prefix")       pfx = "PREFIX + "
          else if (table == "root")         pfx = ""
          else if (table ~ /^copy-mode/)    pfx = "COPY + "
          else                              pfx = table " + "
          # The rows are for recognising a binding, not reading its source.
          if (length(cmd) > 58) cmd = substr(cmd, 1, 55) "..."
          printf "%s%s\t%s\n", pfx, key, cmd
        }' \
    | sort -u | fmt
}

# ---------------------------------------------------------------------------
# Neovim - 208 keymaps already carry a `desc`, so the leader maps are a
# finished cheatsheet with no curation needed.
#
# Two caveats handled here:
#   - nvim_get_keymap returns GLOBAL maps only. The LSP on_attach maps are
#     buffer-local and would silently vanish, so they are merged in statically.
#   - lhs renders <leader> as a literal space; rewrite it for display.
# Cached because loading 37 lazy plugins headless costs a couple of seconds.
# ---------------------------------------------------------------------------

nvim_dump() {
  # Project to plain fields FIRST. A raw nvim_get_keymap entry carries a
  # `callback` holding a Lua function, and vim.json.encode dies on it with
  # "E5108: Cannot serialise function: type not supported".
  nvim --headless -c 'lua
      local out = {}
      for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
        if m.desc and m.desc ~= "" then
          out[#out+1] = { lhs = m.lhs, desc = m.desc }
        end
      end
      io.stderr:write(vim.json.encode(out))' \
    -c 'qa' 2>&1 >/dev/null \
    | jq -r '.[] | [.lhs, .desc] | @tsv' 2>/dev/null || true

  # Buffer-local, set on LspAttach - absent from nvim_get_keymap by design.
  printf 'K\tLSP hover\n'
  printf '<leader>gd\tLSP definition\n'
  printf '<leader>gr\tLSP references\n'
  printf '<leader>ga\tLSP code action\n'
  printf '<leader>gs\tLSP document symbol\n'
  printf '<leader>gk\tLSP signature help\n'
  printf '<leader>gf\tFormat buffer\n'
  printf '<space>rn\tLSP rename\n'
}

render_nvim() {
  key=$(readlink -f "$HOME/.config/nvim/init.lua" 2>/dev/null || echo none)
  cache="$CACHE/nvim.txt"
  if [ -f "$cache" ] && [ "$(head -n1 "$cache")" = "# $key" ]; then
    tail -n +2 "$cache"
    return
  fi
  mkdir -p "$CACHE"
  { printf '# %s\n' "$key"
    nvim_dump | sed 's/^ /<leader>/' | sort -u | fmt
  } > "$cache"
  tail -n +2 "$cache"
}

render() {
  case "$1" in
    hypr) render_hypr ;;
    nvim) render_nvim ;;
    tmux) render_tmux ;;
    *) echo "unknown sheet: $1" >&2; exit 1 ;;
  esac
}

next_sheet() {
  case "$1" in
    hypr) echo nvim ;;
    nvim) echo tmux ;;
    *)    echo hypr ;;
  esac
}

# ---------------------------------------------------------------------------

sheet="hypr"
if [ "${1:-}" = "--print" ] || [ "${1:-}" = "-p" ]; then
  render "${2:-hypr}"
  exit 0
fi
[ $# -gt 0 ] && sheet="$1"

# Toggle: a second press while the popup is up dismisses it.
if pgrep -x rofi >/dev/null 2>&1; then
  pkill -x rofi || true
  rm -f "$STATE" "$NEXT"
  exit 0
fi

trap 'rm -f "$STATE" "$NEXT"' EXIT

while :; do
  printf '%s' "$sheet" > "$STATE"
  rc=0
  render "$sheet" | rofi -dmenu -i \
      -p "$sheet" -theme "$HELP_THEME" \
      -kb-custom-1 Tab -kb-element-next '' \
      >/dev/null || rc=$?

  # 10 = kb-custom-1, i.e. plain Tab reached rofi and it exited cleanly.
  if [ "$rc" = "10" ]; then
    sheet=$(next_sheet "$sheet")
    continue
  fi

  # SUPER+Tab is grabbed by the compositor and never reaches rofi, so that path
  # kills rofi and leaves the next sheet here instead.
  if [ -f "$NEXT" ]; then
    sheet=$(cat "$NEXT")
    rm -f "$NEXT"
    continue
  fi
  break
done
