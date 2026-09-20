{ config, pkgs, ... }:

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

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

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

  users.users.pretamc = {
    isNormalUser = true;
    description = "Pretam";
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

  # Keep the value already present in your original configuration.
  system.stateVersion = "26.05";
}
