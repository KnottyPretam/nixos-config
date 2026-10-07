{ config, pkgs, machine, ... }:

let
  # Claude Code Notification hook - see scripts/claude-notify.sh.
  claudeNotify = pkgs.writeShellApplication {
    name = "claude-notify";
    runtimeInputs = with pkgs; [ jq libnotify tmux coreutils gnugrep ];
    text = ''
      CLAUDE_ICON=${./icons/claude.png}
    '' + builtins.readFile ./scripts/claude-notify.sh;
  };

  # The rhythm prompt hooks - see ~/dev/rhythm-note-taker/src/rhythm/prompts.py.
  #
  # A wrapper of its own rather than home.nix's `rhythm`: configuration.nix
  # cannot see that let-block, and a hook needs neither the vault nor
  # notify-send, because prompts.py deliberately imports nothing else from the
  # package. It follows the same dev-layout rule - nix owns the interface, the
  # Python stays editable without a rebuild.
  rhythmHook = pkgs.writeShellApplication {
    name = "rhythm-hook";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      SRC="$HOME/dev/rhythm-note-taker/src/rhythm"
      [ -d "$SRC" ] || exit 0
      # Silence and exit 0 are both load-bearing, so neither is left to the
      # Python alone. A UserPromptSubmit hook's STDOUT IS APPENDED TO THE
      # MODEL'S CONTEXT, and a non-zero Stop hook is fed back to Claude as a
      # reason the turn may not end - a crash here would otherwise turn into
      # an agent that cannot stop talking.
      python3 "$SRC" "$@" >/dev/null 2>&1 || true
    '';
  };
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = machine.hostName;
  networking.networkmanager.enable = true;

  # Tailscale runs a privileged daemon, so it belongs at the system level -
  # putting the CLI in home.packages would give a `tailscale` with no tailscaled
  # to talk to.
  #
  # NOTE: node authentication is deliberately NOT reproducible. Run
  # `sudo tailscale up` once per machine; identity lives in /var/lib/tailscale.
  # The alternative (authKeyFile) would mean committing a secret to this repo.
  services.tailscale = {
    enable = true;

    # "client" = use exit nodes and subnet routes advertised by others.
    # Use "server"/"both" only if this laptop should advertise routes itself.
    useRoutingFeatures = "client";

    # Opens the UDP port tailscaled uses for direct peer connections; without
    # it traffic still works but falls back to a relay more often.
    openFirewall = true;
  };

  time.timeZone = "America/Phoenix";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Declared from machine.nix. Deliberately NO password here: with
  # users.mutableUsers at its default of true, an existing account keeps the
  # password already in /etc/shadow and `passwd` still works. A hashedPassword
  # in this repo would be a committed secret.
  users.users.${machine.username} = {
    isNormalUser = true;
    description = machine.fullName;
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
      "dialout"
    ];
  };

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # Installs hyprlock system-wide and registers security.pam.services.hyprlock.
  # Without that PAM entry the lock screen cannot authenticate and you would be
  # locked out of your own session.
  programs.hyprlock.enable = true;

  # Graphical login screen
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.displayManager.defaultSession = "hyprland-uwsm";

  # Audio
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
  };

  # Both Electron AI apps gate their Wayland backend behind this; without it
  # they run on XWayland, which is visibly blurry on this 1.5x scaled display.
  # Revert this single line if either app misbehaves on native Wayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  security.rtkit.enable = true;
  security.polkit.enable = true;

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Required by many graphical applications
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Without this, `fc-match monospace` resolves to DejaVu Sans Mono and anything
  # that asks for the generic family - fuzzel, mako, GTK apps - gets no Nerd
  # Font glyphs. The "Mono" variant squeezes icons to one cell, which is what
  # anything assuming a character grid needs.
  fonts.fontconfig.defaultFonts = {
    monospace = [
      "JetBrainsMono Nerd Font Mono"
      "Noto Sans Mono"
      "DejaVu Sans Mono"
    ];
    sansSerif = [
      "Noto Sans"
      "DejaVu Sans"
    ];
    serif = [
      "Noto Serif"
      "DejaVu Serif"
    ];
    emoji = [ "Noto Color Emoji" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    pciutils
    usbutils
  ];

  # Claude Code desktop notifications that name the session. Its built-in
  # notifications (Ghostty OSC 777) carry no session identity, so they are
  # turned off and a Notification hook sends its own instead.
  #
  # Managed settings - Claude's system-level drop-in directory - rather than
  # ~/.claude/settings.json, which Claude writes itself (/config, theme) and so
  # cannot be a read-only Nix file. Read at startup: restart sessions after a
  # switch. The channel shows as locked in /config as a result.
  environment.etc."claude-code/managed-settings.d/50-notifications.json".text =
    builtins.toJSON {
      # The real enum value, read from the installed binary - not the docs'
      # "bell"/"desktop".
      preferredNotifChannel = "notifications_disabled";
      hooks = {
        Notification = [ { hooks = [ { type = "command"; command = "${claudeNotify}/bin/claude-notify"; } ]; } ];

        # The radar's prompt tracking. Files in managed-settings.d are read in
        # sorted order and merged, but whether `hooks` deep-merges or shallow
        # -replaces is not legible in the bundle - so these live in the SAME
        # file as the Notification hook above rather than a 51-*.json of their
        # own. Guessing wrong would silently disable claude-notify.
        #
        # All four events carry a `prompt_id`, which is what joins a prompt to
        # the turn that ends it.

        # `source` here is what history.jsonl cannot give: it separates a
        # prompt you typed from a task notification or a /loop wakeup.
        UserPromptSubmit = [ { hooks = [ { type = "command"; command = "${rhythmHook}/bin/rhythm-hook prompt-sent"; } ]; } ];

        # Marks a turn answered. `background_tasks` is what keeps this honest:
        # a turn parked on background work has not finished.
        Stop = [ { hooks = [ { type = "command"; command = "${rhythmHook}/bin/rhythm-hook prompt-done"; } ]; } ];

        # A turn that DIES never fires Stop. Without this its prompt would read
        # as still running forever, and never leave the lane.
        StopFailure = [ { hooks = [ { type = "command"; command = "${rhythmHook}/bin/rhythm-hook prompt-failed"; } ]; } ];

        # /plan and /model are you operating the tool, not asking it something.
        # This is the proper filter for them; matching a leading "/" is not.
        UserPromptExpansion = [ { hooks = [ { type = "command"; command = "${rhythmHook}/bin/rhythm-hook prompt-expand"; } ]; } ];
      };
    };

  # Keep the value already present in your original configuration.
  system.stateVersion = "26.05";
}
