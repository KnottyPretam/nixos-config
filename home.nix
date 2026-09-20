{ config, pkgs, inputs, ... }:

let
  # ---------------------------------------------------------------------------
  # AI scratchpad
  #
  # `show` is the primitive: make one app's overlay visible, launching it first
  # if it is not running. It is IDEMPOTENT - calling it on an already-visible
  # overlay does nothing, which is what a launcher entry needs.
  #
  # `cycle` (SUPER+G) picks the next app and delegates to `show`, so the
  # app->command mapping exists in exactly one place.
  # ---------------------------------------------------------------------------

  aiScratchpadShow = pkgs.writeShellScriptBin "ai-scratchpad-show" ''
    set -eu
    ws="''${1:?usage: ai-scratchpad-show ai-chatgpt|ai-claude|ai-grok}"

    # `size` takes a muParser expression in Hyprland 0.56 - percentages
    # silently no-op. monitor_w/monitor_h are the LOGICAL size, so this is
    # scale-correct.
    RULES='float; center; size monitor_w*0.6 monitor_h*0.75'

    case "$ws" in
      ai-chatgpt) cmd='chatgpt' ;;
      ai-claude)  cmd='claude-desktop' ;;
      ai-grok)    cmd='chromium --app=https://grok.com --class=grok' ;;
      *) echo "unknown scratchpad: $ws" >&2; exit 1 ;;
    esac

    n=$(hyprctl clients -j \
      | jq --arg w "special:$ws" '[.[] | select(.workspace.name == $w)] | length')
    cur=$(hyprctl monitors -j \
      | jq -r 'first(.[] | select(.focused)) | .specialWorkspace.name // ""')

    if [ "$n" -eq 0 ]; then
      # Bracket exec-rules split on ';' (not ','), and attach by PID+token
      # rather than window class - which is why the unknown app_ids of the two
      # flake apps do not matter. No `silent`: mapping the window opens its
      # special workspace and focuses it, which is what we want here.
      hyprctl dispatch exec "[workspace special:$ws; $RULES] $cmd"
    elif [ "$cur" != "special:$ws" ]; then
      # Dispatch the BARE name - the dispatcher prepends "special:" itself.
      hyprctl dispatch togglespecialworkspace "$ws"
    fi
    # Already visible: do nothing.
  '';

  aiScratchpadCycle = pkgs.writeShellScriptBin "ai-scratchpad-cycle" ''
    set -eu

    # Reports the prefixed name, or "" when no special workspace is open.
    cur=$(hyprctl monitors -j \
      | jq -r 'first(.[] | select(.focused)) | .specialWorkspace.name // ""')

    case "$cur" in
      special:ai-chatgpt) next=ai-claude ;;
      special:ai-claude)  next=ai-grok ;;
      # Last step: close the overlay. Hyprland restores focus to whatever was
      # focused on the underlying workspace.
      special:ai-grok)    hyprctl dispatch togglespecialworkspace ai-grok; exit 0 ;;
      *)                  next=ai-chatgpt ;;
    esac

    # Absolute store path so this does not depend on PATH.
    exec ${aiScratchpadShow}/bin/ai-scratchpad-show "$next"
  '';
in

let
  # Powerline separators. Built from \u escapes rather than pasted literally:
  # these live in the Unicode Private Use Area and are easy to mangle when the
  # file is edited by tools that normalise text.
  plRight = builtins.fromJSON ''"\ue0b0"'';  # right-pointing triangle
  plLeft = builtins.fromJSON ''"\ue0b2"'';   # left-pointing triangle
  plRCap = builtins.fromJSON ''"\ue0b4"'';   # rounded right cap
  plLCap = builtins.fromJSON ''"\ue0b6"'';   # rounded left cap
in
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
    "$HOME/tools/bin"
    "$HOME/.npm-packages/bin"
    "$HOME/.grok/bin"
  ];

  home.sessionVariables = {
    FORGEJO_URL = "https://code.grail.tiberius.com";
  };

  # ---------------------------------------------------------------------------
  # General packages
  # ---------------------------------------------------------------------------

  home.packages = with pkgs; [
    # Agents
    claude-code

    # Claude and ChatGPT desktop apps, from the flake inputs. Grok has no
    # desktop client on any platform, so it runs as a Chromium web-app - see
    # the ai-scratchpad-cycle script below.
    inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
    inputs.chatgpt-desktop.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt-desktop
    chromium

    # SUPER+G cycles a centered AI overlay: ChatGPT -> Claude -> Grok -> back to
    # work. Three special workspaces, one per app; Hyprland allows only one
    # visible per monitor, so they are mutually exclusive by construction and a
    # single `togglespecialworkspace` swaps straight between them.
    #
    # This lives in a script rather than inline in hyprland.conf because
    # hyprlang mangles inline shell: it pre-seeds every environment variable as
    # a `$NAME` substring substitution (colliding with $PATH, $HOME and the
    # config's own $menu/$mainMod), a bare `#` truncates the line anywhere, and
    # `{{ }}` is hyprlang's own expression syntax.
    aiScratchpadShow
    aiScratchpadCycle

    # Hyprland desktop utilities
    # NOTE: waybar and mako are installed by programs.waybar / services.mako
    # below, not here, so they get systemd user units.
    fuzzel
    rofi # NB: `rofi-wayland` was merged into `rofi` and now throws on reference
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
    hyprshot
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

      user.name = "KnottyPretam";
      user.email = "pretam.choudhury@gmail.com";
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
    initLua = builtins.readFile ./dotfiles/nvim/.config/nvim/init.lua;
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
      set -g status-left "#[fg=#769ff0,bg=#1d2230]${plLCap}#[fg=#090c0c,bg=#769ff0,bold]  #S #[fg=#769ff0,bg=#1d2230,nobold]${plRight} "
      set -g status-left-length 40

      # Right: prefix indicator when armed, then the clock on the slate segment.
      set -g status-right "#[fg=#212736,bg=#1d2230]${plLeft}#[fg=#a3aed2,bg=#212736]#{?client_prefix,#[fg=#ff9e64#,bold] PREFIX #[fg=#a3aed2#,nobold],}  %H:%M #[fg=#212736,bg=#1d2230]${plRCap}"
      set -g status-right-length 60

      # Windows: #W is the window NAME, so a manual rename sticks (see
      # automatic-rename below). Current window on light lavender, others slate.
      setw -g window-status-format "#[fg=#a0a9cb,bg=#1d2230] #I:#W "
      setw -g window-status-current-format "#[fg=#a3aed2,bg=#1d2230]${plLeft}#[fg=#090c0c,bg=#a3aed2,bold] #I:#W #[fg=#a3aed2,bg=#1d2230,nobold]${plRight}"
      setw -g window-status-separator ""

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

  # ---------------------------------------------------------------------------
  # Dark mode
  #
  # Three separate mechanisms have to agree, or you get a half-dark desktop:
  #   1. gtk.*            - GTK3/GTK4 apps read ~/.config/gtk-{3.0,4.0}
  #   2. dconf color-scheme - what xdg-desktop-portal reports to Electron,
  #                           Chromium and Firefox as org.freedesktop.appearance
  #   3. qt.*             - Qt apps, which ignore both of the above
  # ---------------------------------------------------------------------------

  gtk = {
    enable = true;

    theme = {
      package = pkgs.gruvbox-gtk-theme;
      name = "Gruvbox-Dark";
    };

    iconTheme = {
      package = pkgs.gruvbox-plus-icons;
      name = "Gruvbox-Plus-Dark";
    };

    font = {
      name = "Noto Sans";
      size = 11;
    };

    # Older GTK3 apps honour this rather than the portal preference.
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  # This is the lever that actually reaches Chromium, Claude Desktop, ChatGPT
  # Desktop and Firefox - they ask xdg-desktop-portal, not GTK.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Gruvbox-Dark";
    icon-theme = "Gruvbox-Plus-Dark";
    cursor-theme = "Bibata-Modern-Classic";
    cursor-size = 24;
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };

  # Sets the cursor for Wayland, XWayland and GTK in one place. Size 24 matches
  # the XCURSOR_SIZE / HYPRCURSOR_SIZE already exported in hyprland.conf.
  # Do NOT also set gtk.cursorTheme - this owns that.
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # ---------------------------------------------------------------------------
  # Default applications
  #
  # Without an explicit http/https default, resolution falls through to
  # mimeinfo.cache, where chatgpt.desktop is first in the candidate list - it
  # legitimately declares http;https, as OpenAI's upstream entry does. The
  # result was that every OAuth `openExternal` launched ChatGPT instead of a
  # browser, so signing in to Claude and ChatGPT could never complete.
  # ---------------------------------------------------------------------------

  # xdg.desktopEntries below is gated on this; without it the entries are
  # silently not generated at all.
  xdg.enable = true;

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "text/html" = "firefox.desktop";

      # Deep links the apps registered for themselves. Carried over from the
      # pre-existing ~/.config/mimeapps.list so OAuth callbacks still land.
      "x-scheme-handler/claude" = "com.anthropic.Claude.desktop";
      "x-scheme-handler/codex" = "chatgpt.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

  # ---------------------------------------------------------------------------
  # Launcher entries for the three AI apps
  #
  # These shadow the packages' own entries by ID ($XDG_DATA_HOME precedes
  # XDG_DATA_DIRS). Without them, launching from rofi runs the app binary, the
  # Electron single-instance handler refocuses the existing window, and that
  # window is parked on a hidden special workspace - so nothing appears. Routing
  # through ai-scratchpad-show makes rofi and SUPER+G behave identically.
  # ---------------------------------------------------------------------------

  xdg.desktopEntries = {
    chatgpt = {
      name = "ChatGPT";
      genericName = "AI assistant";
      comment = "ChatGPT by OpenAI";
      icon = "chatgpt";
      exec = "ai-scratchpad-show ai-chatgpt";
      type = "Application";
      categories = [ "Utility" "Development" ];

      # http/https deliberately NOT declared here - that candidacy is what
      # hijacked the browser. codex:// is kept so OAuth callbacks still land.
      mimeType = [ "x-scheme-handler/codex" ];

      settings.StartupWMClass = "Chatgpt"; # upstream omits this; waybar needs it
    };

    "com.anthropic.Claude" = {
      name = "Claude";
      genericName = "AI Assistant";
      comment = "Desktop application for Claude.ai";
      icon = "claude-desktop";
      exec = "ai-scratchpad-show ai-claude";
      type = "Application";
      categories = [ "Utility" "Development" ];
      mimeType = [ "x-scheme-handler/claude" ];
      settings.StartupWMClass = "com.anthropic.Claude";
    };

    # Grok ships no .desktop at all, so it never appeared in the launcher.
    grok = {
      name = "Grok";
      genericName = "AI assistant";
      comment = "Grok by xAI";
      icon = "chromium";
      exec = "ai-scratchpad-show ai-grok";
      type = "Application";
      categories = [ "Utility" ];
      settings.StartupWMClass = "chrome-grok.com__-Default";
    };
  };

  services.hyprpaper = {
    enable = true;

    settings = {
      splash = false;

      # hyprpaper 0.8.x config shape. An empty `monitor` means every output.
      wallpaper = [
        {
          monitor = "";
          path = "${config.home.homeDirectory}/Pictures/wallpapers/dragon.jpg";
          fit_mode = "cover";
        }
      ];
    };
  };
}
