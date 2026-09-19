# dotfiles

Personal config, managed with [GNU Stow](https://www.gnu.org/software/stow/).
Each top-level directory is a stow package whose contents mirror `$HOME`.

## Usage

```
sudo apt install stow   # or your distro's equivalent

cd /path/to/this/repo
stow bash claude git hypr nvim starship tmux
```

`.stowrc` sets the target to `$HOME` (stow expands environment variables and `~`
in `.stowrc`), so `stow <package>` run from the repo root symlinks straight into
your home directory without needing `-t`, on any machine.

If a target file already exists (e.g. a fresh `~/.bashrc`), stow will refuse
rather than overwrite it. Move the existing file aside first, or use
`stow --adopt <package>` to pull the live file into the repo, then check
`git diff` before committing.

To remove a package's symlinks: `stow -D <package>`.

## Packages

- **bash** — `.bashrc`
- **claude** — Claude Code global config (`CLAUDE.md`, `settings.json`,
  hand-authored skills, plugin marketplace/install records). See
  `docs/claude.md` for plugin install commands and other notes.
- **git** — global `.config/git/ignore`
- **hypr** — Hyprland and hypridle (`.config/hypr/`). Assumes waybar, swaync,
  kitty, wofi and dolphin are installed — those aren't vendored here.
- **nvim** — Neovim config (lazy.nvim, LSP, Avante, Obsidian integration)
- **starship** — `starship.toml`
- **tmux** — `.config/tmux/tmux.conf` (tmux 3.1+ reads this path natively, so no
  `~/.tmux.conf` symlink is needed). Uses
  [tpm](https://github.com/tmux-plugins/tpm) — clone it to `~/.tmux/plugins/tpm`
  separately, it isn't vendored here. Install the plugins with prefix + `I`.

## Notes

- Secrets are never committed. `~/.bashrc` sources `~/.bashrc.local`
  (untracked) for anything like `FORGEJO_TOKEN`.
- Claude Code plugin marketplaces/caches aren't vendored — only
  `installed_plugins.json` and `known_marketplaces.json` are tracked as a
  record of what's installed. Re-fetch them with the commands in
  `docs/claude.md`.
- The stow target itself is portable, but some tracked configs still hardcode
  `/home/pchoudhury` from the machine they were authored on: `claude`'s hooks and
  permissions, `bash`'s `STM32_PRG_PATH`, and `nvim`'s avante API-key command.
  Fix those up by hand on a machine with a different `$HOME`.
