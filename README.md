# nixos-config

NixOS + Hyprland for a ThinkPad, as a flake. Home Manager runs as a NixOS
module, so one `nixos-rebuild switch` applies both the system and the user
environment.

```
flake.nix                 inputs; nixpkgs plus a SEPARATE input for claude-code
configuration.nix         system: boot, hyprland, audio, fonts, tailscale,
                          Claude Code managed settings + hooks
home.nix                  everything user-level, and the scripts the keybinds call
machine.nix               >>> PER-MACHINE: username, hostname. Edit on a new box.
env.nix                   >>> PER-MACHINE: vault paths, Forgejo URL. Same.
hardware-configuration.nix  machine-specific. REGENERATE on a new box (see below)
pkgs/claude-code-manifest.json  pinned Claude Code release
dotfiles/                 hypr, nvim, tmux, waybar, starship, rofi, claude
scripts/                  shell for the bigger keybinds (help-sheet, claude-notify)
wallpapers/               rotated one step per boot
icons/                    desktop-entry icons for the web-apps
```

---

## Bringing up a new machine

### 1. Install NixOS, then clone

```sh
nix-shell -p git
git clone git@github.com:KnottyPretam/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

### 2. Regenerate the hardware config — do not skip this

`hardware-configuration.nix` in this repo pins **this laptop's** disk UUIDs.
Using it unchanged on different hardware will not boot.

```sh
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

### 3. Set the username and hostname

Edit **`machine.nix`**:

```nix
{ username = "you"; hostName = "thisbox"; fullName = "Your Name"; }
```

This is declarative config, so whatever is named here is the account and
hostname the build **creates**. Building this flake unchanged on another
computer is what gives that computer this user and the hostname `nixos` — it
does not read the machine, it imposes what this file says.

Pointing `username` at an account that already exists does **not** touch its
password. Nothing in this repo sets one (`hashedPassword` is null) and
`users.mutableUsers` is at its default of `true`, so `/etc/shadow` is left
alone and `passwd` keeps working. A password hash here would be a committed
secret.

`hostName` is also the flake output name, so build with `.#<hostName>` — or
just `--flake ~/nixos-config`, which uses the machine's current hostname.

### 4. Set the per-machine paths

Edit **`env.nix`** — vault locations and the Forgejo URL. Nothing else needs
touching. These values are exported to every session AND substituted into the
Claude dotfiles at build time.

### 5. Stage everything, then build

```sh
git add -A        # see "the flake reads the git tree" below - this is load-bearing
sudo nixos-rebuild switch --flake ~/nixos-config        # uses this host's name
```

### 6. The steps that cannot be reproducible

| | |
|---|---|
| `sudo tailscale up` | node identity lives in `/var/lib/tailscale`, not in git. An auth key in this repo would be a committed secret. |
| `git clone <vault> ~/vaults/root-engine` | **Clone before first use.** The note app and the session-notes skill `mkdir -p` their directories, and a non-empty directory makes `git clone` refuse. |
| `git clone git@github.com:KnottyPretam/rhythm-note-taker.git ~/dev/rhythm-note-taker` | the note app's Python is deliberately NOT vendored here — see "rhythm" below. |
| `~/.claude/forgejo-get.sh` | the session-notes skill calls it; it holds a token, so it is not in this repo. Copy it from the old machine. |
| sign in to the web-apps | ChatGPT / Claude / Grok, once each, on first launch. |

### 7. Verify

```sh
hyprctl binds -j | jq '[.[]|select(.has_description)]|length'   # every bind labelled
hyprctl configerrors                                             # empty
systemctl --user status hypridle waybar hyprpaper
echo $HOME_VAULT                                                 # from env.nix
rhythm board activity | jq '.columns[].title'
help-sheet --print ghostty | head -3
```

---

## Keybindings

**SUPER+SHIFT+H** is the cheatsheet — four searchable pages (Hyprland, Neovim,
tmux, Ghostty), Tab to cycle. Every page is generated from the live config, so
it cannot go stale. The Hyprland page works because *every* bind is written as
`bindd` with a description.

The non-obvious ones:

| | |
|---|---|
| `SUPER+G` | AI overlay — toggles the last app you used (ChatGPT / Claude / Grok) |
| `SUPER+Tab` | cycles the three, but ONLY while an overlay is focused |
| `SUPER+N` | rhythm note app (notepad / activity board / project board / radar) |
| `SUPER+C` | new note, only when the rhythm notepad is focused |
| `SUPER+I` | capture an offline activity for the radar |
| `SUPER+1..0` | switch workspace **and** dismiss any overlay, even the current workspace |
| `SUPER+R` / `SUPER+F` | launcher: fuzzel / rofi |
| `SUPER+SHIFT+H` | this cheatsheet |

In nvim, `<leader>0` returns to the first real file of the session.

---

## Things that cost hours to work out

**The flake reads the git TREE, not the working directory.** An untracked file
is invisible to evaluation: the build fails with "file not found" or silently
uses an older copy. `git add -A` after adding any new file, before rebuilding.
This is the single most common way a rebuild here goes wrong.

**Before diagnosing "it didn't work", check it was applied.** Compare
`readlink -f /run/current-system` against the path the build printed. Several
"still broken" reports here were simply not switched in yet.

**Ghostty is single-instance.** A new window comes from the existing process,
which loaded its config at startup — so config changes do NOT apply to a "new
terminal". Quit every ghostty window (or `ctrl+shift+,`) to pick them up.

**Over ssh, ghostty needs its terminfo installed on the remote.** Enabled via
`shell-integration-features = …,ssh-env,ssh-terminfo`. Without it `TERM` stays
`xterm-ghostty`, which remote hosts do not know, and tmux there dies with
"missing or unsuitable terminal". Also note the tmux *server* caches the
environment it started with, so `GHOSTTY_SHELL_FEATURES` can be stale inside
tmux until `tmux kill-server`.

**hypridle logs `Config has errors: No rules configured` on purpose.** It has
no listeners, so nothing blanks, locks or suspends on a timer. It stays enabled
only for its `general` block, which locks the session before a lid-close
suspend. Closing the lid is the only thing that sleeps this machine, via
logind's `HandleLidSwitch`. To restore idle behaviour, the old timeouts are in
a comment in `dotfiles/hypr/.config/hypr/hypridle.conf`.

**Hyprland fails some rules silently.** `size 60% 75%` parses but does nothing
— percentages are not muParser operators, and `hyprctl configerrors` stays
clean. Use expressions over `monitor_w`/`monitor_h`, or `maximize`, which also
respects waybar's reserved 32px (a literal full-size window hides under it).

**`SUPER+1..0` go through `ws-go`, not `workspace`.** Hyprland's native
`binds:hide_special_on_workspace_change` cannot cover switching to the
workspace you are already on — that dispatch returns early, so the overlay
would stay up.

**mason's language servers cannot run on NixOS.** They are generic-linux ELF
binaries. Every LSP and formatter comes from `home.nix` instead, and mason is
configured with `PATH = "skip"` so it cannot shadow them.

**pip/uv wheels with native code need help.** They expect a system
`libstdc++.so.6`, which NixOS does not provide on a standard path, and `nix-ld`
does not fix it when the interpreter is Nix's own Python. The `cgc` wrapper in
`home.nix` shows the pattern: set `LD_LIBRARY_PATH` for that one program. It
also needs network on first run, since `uvx` fetches it.

**Claude Code's managed settings are read at startup.** They live in
`/etc/claude-code/managed-settings.d/` (written by `configuration.nix`) rather
than `~/.claude/settings.json`, which Claude writes itself and so cannot be a
read-only Nix symlink. Restart Claude sessions after a switch.

**`~/.claude/CLAUDE.md` and the skills are read-only store symlinks.** Edit
`dotfiles/claude/` and rebuild; `/memory` cannot save changes to them.

---

## rhythm (the note app)

Lives in **`~/dev/rhythm-note-taker`**, its own repo, deliberately not vendored
into this flake: an edit then takes effect on the next invocation with no
rebuild. Nix owns only the interface — the binary name, the PATH closure, the
vault path.

To promote it into the flake later:

```sh
cp -r ~/dev/rhythm-note-taker/src/rhythm ~/nixos-config/scripts/rhythm
git add -A
# then swap SRC for ${./scripts/rhythm} in home.nix
```

If the directory is missing, `SUPER+N` sends a notification saying so rather
than failing invisibly.

---

## Updating

```sh
nix flake update nixpkgs          # everything
nix flake update nixpkgs-claude   # Claude Code only
sudo nixos-rebuild switch --flake ~/nixos-config#nixos
```

Claude Code sits on its own nixpkgs input so it can move without dragging the
rest of the system with it. It is currently pinned harder still: a `manifest`
override in `flake.nix` points at `pkgs/claude-code-manifest.json`, because
nixpkgs lagged the version needed. **Delete that override once nixpkgs catches
up**, or refresh the manifest with the commands in the comment above it.

`sudo` is required for `nixos-rebuild switch`. `nixos-rebuild build` needs no
privileges and is the safe way to check a change compiles.
