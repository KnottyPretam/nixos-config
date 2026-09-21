# Machine-specific settings. Change a value here, then rebuild:
#   sudo nixos-rebuild switch --flake ~/nixos-config#nixos
#
# Each name is exported to every session - login shells, Hyprland, anything
# launched from it (nvim, Claude Code) - via home.sessionVariables. A running
# program keeps the old value until restarted; a new value needs a re-login to
# reach Hyprland itself.
#
# The Claude Code dotfiles (CLAUDE.md, skills/session-notes) also get these
# values written in at build time, since Claude's Write tool does not expand
# $VARS and skill permission patterns must be literal paths.
{ home }:
{
  # Default vault for obsidian.nvim and the <leader>ov / <leader>oh panel.
  HOME_VAULT = "${home}/vaults/root-engine";

  # Vault holding for Tiberius
  TIBERIUS_VAULT = "${home}/vaults/tiberius";

  FORGEJO_URL = "https://code.grail.tiberius.com";
}
