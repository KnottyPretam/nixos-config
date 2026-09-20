{ config, pkgs, ... }:

{
  # ---------------------------------------------------------------------------
  # Home Manager identity
  # ---------------------------------------------------------------------------

  home.username = "pretamc";
  home.homeDirectory = "/home/pretamc";

  # For a new installation created with NixOS 26.05.
  # Once set, do not routinely change this during upgrades.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # Make ~/.local/bin available for Claude Code and other user-installed tools.
  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # ---------------------------------------------------------------------------
  # General packages
  # ---------------------------------------------------------------------------

  home.packages = with pkgs; [
    # Agents
    claude-code

    # Hyprland desktop utilities
    # NOTE: waybar and mako are installed by programs.waybar / services.mako
    # below, not here, so they get systemd user units.
    fuzzel
    networkmanagerapplet
    pavucontrol
    brightnessctl
    playerctl
    libnotify

    # Wayland tools
    wl-clipboard
    grim
    slurp
    swappy
    grimblast
    yazi

    # Terminal utilities
    ripgrep
    fd
    jq
    yq-go
    tree
    file
    which
    unzip
    zip
    curl
    wget
    htop
    btop
    bottom
    procs
    dust
    duf
    fastfetch

    # Git utilities
    git-lfs
    delta
    lazygit

    # Build and development tools
    gcc
    # nvim-treesitter's main branch builds parsers by shelling out to
    # `tree-sitter build`; the master-era gcc compile path is gone, so gcc
    # alone is not enough.
    tree-sitter
    clang-tools
    gnumake
    cmake
    ninja
    pkg-config
    gdb
    valgrind

    # Languages and scripting
    python3
    nodejs

    # Shell and Nix tools
    shellcheck
    shfmt
    nixfmt
    nil

    # Fonts
    nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.enable = true;

  # Wallpaper lives in the repo, so a fresh machine gets it from the flake.
  # Materializing it at a fixed path (rather than referencing the /nix/store
  # path directly) lets hyprpaper.conf and hyprlock.conf name it literally.
  home.file."Pictures/wallpapers/dragon.jpg".source = ./wallpapers/dragon.jpg;

  # ---------------------------------------------------------------------------
  # Bash
  # ---------------------------------------------------------------------------

  programs.bash = {
    enable = true;
    enableCompletion = true;

    historyControl = [
      "ignoredups"
      "ignorespace"
    ];

    historySize = 100000;
    historyFileSize = 100000;

    shellAliases = {
      # `ls` is deliberately NOT aliased: eza is not flag-compatible with GNU
      # ls (eza's -t is --time=FIELD, so `ls -ltr` errors out). Leaving ls as
      # the real thing keeps every familiar flag working; eza gets its own
      # names below.
      l = "eza --icons";
      ll = "eza -lah --icons --git";
      la = "eza -a --icons";
      lla = "eza -la --icons --git";
      lt = "eza --tree --level=2 --icons";

      # GNU equivalents: `ls -ltr` and `ls -lt`.
      ltr = "eza -l --icons --git --sort=date";
      lnew = "eza -l --icons --git --sort=date --reverse";

      cat = "bat";
      grep = "rg";
      find = "fd";

      gs = "git status";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline --graph --decorate";
      gd = "git diff";
      lg = "lazygit";

      rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#nixos";
      check-system = "nix flake check ~/nixos-config";
      update-system = "cd ~/nixos-config && nix flake update && sudo nixos-rebuild switch --flake .#nixos";

      c = "clear";
      ".." = "cd ..";
      "..." = "cd ../..";
    };

    initExtra = ''
      # Use vi-style editing in Bash.
      set -o vi
    '';
  };

  # ---------------------------------------------------------------------------
  # Starship — Gruvbox
  # ---------------------------------------------------------------------------

  programs.starship = {
    enable = true;
    enableBashIntegration = true;

    # `settings` left unset so the module skips generating starship.toml and the
    # verbatim dotfile owns it - same pattern as hypr and waybar.
  };

  xdg.configFile."starship.toml".source =
    ./dotfiles/starship/.config/starship.toml;

  # ---------------------------------------------------------------------------
  # Better shell utilities
  # ---------------------------------------------------------------------------

  programs.eza = {
    enable = true;

    # The module's bash integration unconditionally aliases `ls` to eza and
    # offers no way to opt out of just that one alias, so integration is off
    # and the aliases are declared in programs.bash.shellAliases instead.
    enableBashIntegration = false;

    icons = "auto";
    git = true;
  };

  programs.bat = {
    enable = true;

    config = {
      theme = "gruvbox-dark";
      style = "numbers,changes,header";
    };
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    options = [ "--cmd cd" ];
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  # ---------------------------------------------------------------------------
  # Git
  # ---------------------------------------------------------------------------

  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      init.defaultBranch = "main";
      core.editor = "nvim";
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";

      pull.rebase = false;
      push.autoSetupRemote = true;
      fetch.prune = true;

      merge.conflictStyle = "zdiff3";
      diff.colorMoved = "default";

      delta = {
        navigate = true;
        line-numbers = true;
        side-by-side = false;
        syntax-theme = "gruvbox-dark";
      };

      # Uncomment and fill these in:
      #
      # user.name = "Pretam Choudhury";
      # user.email = "your-email@example.com";
    };
  };

  # ---------------------------------------------------------------------------
  # Neovim
  # ---------------------------------------------------------------------------
  programs.neovim = {
    enable = true;

    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    withNodeJs = true;
    withPython3 = true;

    # The neovim module owns ~/.config/nvim/init.lua (it writes the node/python
    # provider stanzas there), so the dotfile init.lua has to go through
    # extraLuaConfig rather than a competing xdg.configFile entry.
    extraLuaConfig = builtins.readFile ./dotfiles/nvim/.config/nvim/init.lua;
  };

  # Everything else under ~/.config/nvim. Note these paths point at the *inner*
  # .config/nvim of the stow package, not the package root.
  #
  # lazy-lock.json and harper-dict.txt are deliberately NOT managed here: lazy
  # rewrites the lockfile on :Lazy sync/update and harper appends to the
  # dictionary, and a read-only /nix/store symlink would make those writes fail.
  xdg.configFile = {
    "nvim/lua" = {
      source = ./dotfiles/nvim/.config/nvim/lua;
      recursive = true;
    };

    "nvim/.luarc.json".source = ./dotfiles/nvim/.config/nvim/.luarc.json;
  };

  # ---------------------------------------------------------------------------
  # Tmux
  # ---------------------------------------------------------------------------

  programs.tmux = {
    enable = true;

    terminal = "tmux-256color";
    prefix = "C-a";
    keyMode = "vi";

    escapeTime = 0;
    historyLimit = 100000;

    mouse = true;
    focusEvents = true;
    clock24 = true;

    plugins = with pkgs.tmuxPlugins; [
      vim-tmux-navigator

      sessionist
      fpp
      open

      {
        plugin = resurrect;

        extraConfig = ''
          set -g @resurrect-strategy-nvim "session"
          set -g @resurrect-capture-pane-contents "on"
        '';
      }

      {
        plugin = continuum;

        extraConfig = ''
          set -g @continuum-restore "on"
          set -g @continuum-save-interval "15"
        '';
      }

      copycat
      yank
    ];

    extraConfig = ''
      # Reload Home Manager's generated tmux configuration.
      unbind r
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux configuration reloaded"

      # True-color support for Ghostty and other terminals.
      set -as terminal-features ",xterm-ghostty:RGB"
      set -as terminal-features ",xterm-256color:RGB"

      # Vim-style pane navigation.
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R

      # Pane splitting.
      bind-key q split-window -h
      bind-key w split-window -v

      # Create new panes in the current pane's directory.
      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # ---------------------------------------------------------------------
      # Status bar - Tokyo Night, using the exact palette from starship's
      # tokyo-night preset:
      #   #a3aed2  light lavender   #769ff0  blue
      #   #394260  slate            #212736  darker
      #   #1d2230  darkest (bar bg) #e3e5e5  near-white
      # ---------------------------------------------------------------------
      set-option -g status-position top
      set -g status-interval 5
      set -g status-justify left
      set -g status-style "bg=#1d2230,fg=#a0a9cb"

      # Left: session name on tokyo-night blue, closed with a powerline chevron.
      set -g status-left "#[fg=#090c0c,bg=#769ff0,bold]  #S #[fg=#769ff0,bg=#1d2230,nobold]"
      set -g status-left-length 40

      # Right: prefix indicator when armed, then the clock on the slate segment.
      set -g status-right "#[fg=#212736,bg=#1d2230]#[fg=#a3aed2,bg=#212736]#{?client_prefix,#[fg=#ff9e64#,bold] PREFIX #[fg=#a3aed2#,nobold],}  %H:%M "
      set -g status-right-length 60

      # Windows: #W is the window NAME, so a manual rename sticks (see
      # automatic-rename below). Current window on light lavender, others slate.
      setw -g window-status-format "#[fg=#394260,bg=#1d2230]#[fg=#a0a9cb,bg=#394260] #I:#W #[fg=#394260,bg=#1d2230]"
      setw -g window-status-current-format "#[fg=#a3aed2,bg=#1d2230]#[fg=#090c0c,bg=#a3aed2,bold] #I:#W #[fg=#a3aed2,bg=#1d2230,nobold]"
      setw -g window-status-separator " "

      # Keep manually-set window names.
      #   automatic-rename: tmux renaming the window to the running command -
      #     this was ON, which is what wiped names set with prefix + ,
      #   allow-rename: the same thing driven by an app escape sequence.
      setw -g automatic-rename off
      set -g allow-rename off
      set -g set-titles off

      # Panes, messages, copy mode.
      set -g pane-border-style "fg=#394260"
      set -g pane-active-border-style "fg=#769ff0"
      set -g message-style "bg=#394260,fg=#e3e5e5"
      set -g message-command-style "bg=#394260,fg=#e3e5e5"
      setw -g mode-style "bg=#769ff0,fg=#090c0c"
    '';
  };

  # ---------------------------------------------------------------------------
  # Ghostty
  # ---------------------------------------------------------------------------

  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;

    settings = {
      "font-family" = "JetBrainsMono Nerd Font";
      "font-size" = 12;

      "window-padding-x" = 8;
      "window-padding-y" = 8;

      # ~30% transparent so the wallpaper shows through slightly.
      # background-blur is deliberately NOT set: on some ghostty builds it
      # conflicts with Hyprland's own blur and the window renders solid.
      "background-opacity" = 0.7;

      "cursor-style" = "block";
      "cursor-style-blink" = false;

      "copy-on-select" = "clipboard";
      "confirm-close-surface" = false;

      # Gruvbox Dark Hard
      background = "1d2021";
      foreground = "ebdbb2";

      palette = [
        "0=#282828"
        "1=#cc241d"
        "2=#98971a"
        "3=#d79921"
        "4=#458588"
        "5=#b16286"
        "6=#689d6a"
        "7=#a89984"
        "8=#928374"
        "9=#fb4934"
        "10=#b8bb26"
        "11=#fabd2f"
        "12=#83a598"
        "13=#d3869b"
        "14=#8ec07c"
        "15=#ebdbb2"
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Firefox
  # ---------------------------------------------------------------------------

  programs.firefox = {
    enable = true;
  };

  # ---------------------------------------------------------------------------
  # Hyprland desktop
  #
  # The .conf files under ./dotfiles/hypr are the source of truth; Home Manager
  # materializes them verbatim into ~/.config/hypr so a rebuild on any machine
  # reproduces the desktop exactly.
  # ---------------------------------------------------------------------------

  wayland.windowManager.hyprland = {
    enable = true;

    # Hyprland and its portal come from programs.hyprland in configuration.nix.
    package = null;
    portalPackage = null;

    # uwsm owns graphical-session.target; don't let Home Manager create a
    # competing hyprland-session.target.
    systemd.enable = false;

    # home.stateVersion 26.05 defaults this to "lua", which would write our
    # hyprlang config verbatim into hyprland.lua and fail to parse. The dotfile
    # is hyprlang, so write hyprland.conf.
    configType = "hyprlang";

    extraConfig = builtins.readFile ./dotfiles/hypr/.config/hypr/hyprland.conf;
  };

  # `settings` is deliberately left empty: the module only generates
  # hypr/hypridle.conf when settings is non-empty, so the verbatim dotfile below
  # stands while we still get the systemd user unit.
  services.hypridle.enable = true;

  xdg.configFile."hypr/hypridle.conf".source =
    ./dotfiles/hypr/.config/hypr/hypridle.conf;

  programs.hyprlock = {
    enable = true;

    # Provided system-wide by programs.hyprlock in configuration.nix, which also
    # sets up PAM.
    package = null;

    extraConfig = builtins.readFile ./dotfiles/hypr/.config/hypr/hyprlock.conf;
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    # `settings` and `style` are left unset on purpose: the module only writes
    # waybar/config and waybar/style.css when they are non-empty, so the
    # verbatim dotfiles below own those paths.
  };

  xdg.configFile."waybar/config.jsonc".source =
    ./dotfiles/waybar/.config/waybar/config.jsonc;

  xdg.configFile."waybar/style.css".source =
    ./dotfiles/waybar/.config/waybar/style.css;

  services.mako.enable = true;

  services.hyprpaper = {
    enable = true;

    settings = {
      ipc = "on";
      splash = false;

      preload = [ "${config.home.homeDirectory}/Pictures/wallpapers/dragon.jpg" ];
      wallpaper = [ ",${config.home.homeDirectory}/Pictures/wallpapers/dragon.jpg" ];
    };
  };
}
