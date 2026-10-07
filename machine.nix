# WHO AND WHERE THIS IS. Edit this file, and env.nix, on a new machine.
#
# NixOS config is DECLARATIVE: whatever is named here is the account and
# hostname the build creates. That is why building this flake unchanged on
# another computer gave it this user and the hostname "nixos" - it was not
# reading the machine, it was imposing what this file says.
#
# Changing `username` to an account that already exists does NOT touch its
# password: nothing here sets one, and users.mutableUsers defaults to true, so
# /etc/shadow is left alone and `passwd` keeps working as normal.
#
# `hostName` is also the flake output name, so after changing it build with
#     sudo nixos-rebuild switch --flake ~/nixos-config#<hostName>
{
  username = "pretamc";
  hostName = "nixos";

  # Shown in `users.users.<name>.description`, i.e. on the login screen.
  fullName = "Pretam";
}
