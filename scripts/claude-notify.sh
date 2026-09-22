# Claude Code `Notification` hook: a desktop notification that names the session.
# The hook's JSON payload arrives on stdin. Wired up from configuration.nix via
# /etc/claude-code/managed-settings.d/50-notifications.json.
#
# Always exits 0: a failing hook would surface as an error inside Claude, and a
# missing notification is the lesser problem.

input=$(cat)
field() { jq -r --arg k "$1" '.[$k] // ""' <<<"$input" 2>/dev/null || true; }

sid=$(field session_id)
cwd=$(field cwd)
transcript=$(field transcript_path)
msg=$(field message)
kind=$(field notification_type)
[ -n "$msg" ] || msg="Claude needs your attention"

# The hook payload carries no session name, so look it up.
name=""
pane=""

# 1. The live-session registry: one ~/.claude/sessions/<pid>.json per running
#    session, holding the /rename (or auto-generated) name and, inside tmux,
#    the pane - e.g. "Home:@2.%2". Undocumented, hence the fallbacks.
for f in "$HOME"/.claude/sessions/*.json; do
  [ -f "$f" ] || continue
  if [ "$(jq -r '.sessionId // ""' "$f" 2>/dev/null || true)" = "$sid" ]; then
    name=$(jq -r '.name // ""' "$f" 2>/dev/null || true)
    pane=$(jq -r '.tmux // ""' "$f" 2>/dev/null || true)
    break
  fi
done

# 2. The last /rename recorded in the transcript. It is appended as its own
#    line when the rename happens - not on the transcript's first line.
if [ -z "$name" ] && [ -f "$transcript" ]; then
  name=$(grep -F '"type":"custom-title"' "$transcript" 2>/dev/null | tail -n 1 \
    | jq -r '.customTitle // ""' 2>/dev/null || true)
fi

# 3. The directory it runs in.
[ -n "$name" ] || name=$(basename "${cwd:-unknown}")

where="${cwd/#"$HOME"/\~}"
if [ -n "$pane" ]; then
  # "Home:@2.%2" -> ask tmux for the human "Home:2"; if the server can't be
  # reached, fall back to just the session name before the colon.
  loc=$(tmux display-message -p -t "${pane##*.}" '#S:#I' 2>/dev/null || true)
  where="$where · tmux ${loc:-${pane%%:*}}"
fi

urgency=normal
[ "$kind" = "permission_prompt" ] && urgency=critical # it is blocking on you

notify-send --app-name="Claude Code" --icon="$CLAUDE_ICON" --urgency="$urgency" \
  "Claude · $name" "$msg"$'\n'"$where" 2>/dev/null || true
exit 0
