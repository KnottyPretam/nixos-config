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
    # Hyprland desktop utilities
    waybar
    fuzzel
    mako
    hyprpaper
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
    clang
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
      ls = "eza --icons";
      l = "eza --icons";
      ll = "eza -lah --icons --git";
      la = "eza -a --icons";
      lt = "eza --tree --level=2 --icons";

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

    settings = {
      add_newline = true;
      palette = "gruvbox_dark";

      format = "$username$hostname$directory$git_branch$git_status$nix_shell$python$cpp$cmd_duration$line_break$character";

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vimcmd_symbol = "[❮](bold green)";
      };

      directory = {
        style = "bold blue";
        truncation_length = 4;
        truncate_to_repo = false;
        read_only = " 󰌾";
      };

      git_branch = {
        symbol = " ";
        style = "bold purple";
      };

      git_status = {
        style = "bold yellow";
        conflicted = "=";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        untracked = "?\${count}";
        stashed = "$";
        modified = "!\${count}";
        staged = "+\${count}";
        renamed = "»\${count}";
        deleted = "✘\${count}";
      };

      nix_shell = {
        symbol = " ";
        style = "bold blue";
      };

      python = {
        symbol = " ";
        style = "bold yellow";
      };

      cpp = {
        symbol = " ";
        style = "bold blue";
      };

      cmd_duration = {
        min_time = 2000;
        format = "took [$duration]($style) ";
        style = "bold yellow";
      };

      palettes.gruvbox_dark = {
        black = "#282828";
        red = "#cc241d";
        green = "#98971a";
        yellow = "#d79921";
        blue = "#458588";
        purple = "#b16286";
        aqua = "#689d6a";
        white = "#a89984";
        orange = "#d65d0e";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Better shell utilities
  # ---------------------------------------------------------------------------

  programs.eza = {
    enable = true;
    enableBashIntegration = true;
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
  };
  
  xdg.configFile."nvim" = {
    source = ./dotfiles/nvim;
    recursive = true;
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

      {
        plugin = catppuccin;

        extraConfig = ''
          set -g @catppuccin_flavor "latte"
          set -g @catppuccin_window_status_style "rounded"
          set -g @catppuccin_window_current_text "#W"
        '';
      }

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

      # Status bar.
      set-option -g status-position top
      set -g status-left ""
      set -g status-right "#{E:@catppuccin_status_application} #{E:@catppuccin_status_session}"

      # Retain the terminal background behind the status line.
      set -g status-style bg=default
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
}
