{ config, pkgs, ... }:

let
  # The machine-specific variables - see env.nix.
  env = import ./env.nix { home = config.home.homeDirectory; };

  # Read a file and replace each ${NAME} with its env.nix value (plus ${HOME}),
  # so the Claude dotfiles get literal paths. They must: Claude's Write tool
  # does not expand $VARS, and skill allowed-tools patterns match the command
  # as written. Any other ${...} - shell variables like ${DATE} - is left as is.
  substEnv =
    file:
    let
      vars = env // { HOME = config.home.homeDirectory; };
    in
    builtins.replaceStrings
      (map (n: "$" + "{" + n + "}") (builtins.attrNames vars))
      (builtins.attrValues vars)
      (builtins.readFile file);

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

  # ---------------------------------------------------------------------------
  # Wallpaper: advance one step per session (boot or Hyprland restart).
  # Deliberately NOT a timer - it must not change while the session is running.
  # ---------------------------------------------------------------------------
  wallpaperRotate = pkgs.writeShellScript "wallpaper-rotate" ''
    set -eu

    # The store copy of ./wallpapers. Because this is a store path, the script
    # (and so the unit's ExecStart) changes whenever the folder changes, which
    # is what makes "rebuild to pick up a new image" work.
    dir=${./wallpapers}

    # Persisting the index is what makes the sequence survive a reboot -
    # without it every session would start at the same image.
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-index"

    # Glob expansion is sorted, so this is a stable sequence.
    set -- "$dir"/*
    [ -e "$1" ] || exit 0

    i=0
    [ -r "$state" ] && i=$(cat "$state") || true
    case "$i" in ""|*[!0-9]*) i=0 ;; esac
    i=$(( i % $# ))          # modulo, so removing an image cannot overrun

    eval "pick=\''${$(( i + 1 ))}"
    mkdir -p "$(dirname "$state")"
    echo $(( (i + 1) % $# )) > "$state"

    # hyprpaper starts in parallel with us; its socket may not be up yet.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if hyprctl hyprpaper wallpaper ",$pick"; then exit 0; fi
      sleep 1
    done
    echo "wallpaper-rotate: hyprpaper did not answer" >&2
    exit 1
  '';

  # ---------------------------------------------------------------------------
  # Keyboard-shortcut cheatsheets (SUPER+SHIFT+H)
  #
  # The script lives in its own file rather than inline here: it is ~190 lines
  # of awk and jq, and Nix indented strings would need every ''${...} and bare
  # '' escaped. readFile sidesteps that entirely.
  # ---------------------------------------------------------------------------
  helpSheet = pkgs.writeShellApplication {
    name = "help-sheet";
    runtimeInputs = with pkgs; [
      hyprland jq gawk tmux neovim rofi coreutils procps gnused
      # For `ghostty +list-keybinds`. Same derivation programs.ghostty
      # installs, so this adds nothing to the closure.
      ghostty
    ];
    text = ''
      HELP_THEME=${./dotfiles/rofi/keybindings.rasi}
      export HELP_THEME
    '' + builtins.readFile ./scripts/help-sheet.sh;
  };

  # CodeGraphContext, for the cgc-refresh Claude skill. Not in nixpkgs, and its
  # ~25 Python deps make hand-packaging a poor trade, so uvx fetches it into
  # ~/.cache/uv on first run. The version pin here is what keeps it
  # reproducible. Two NixOS-specific details, both observed failing without:
  #   - LD_LIBRARY_PATH: the kuzu wheel dlopens libstdc++.so.6, which has no
  #     standard path on NixOS. cgc misreports this as a "Database Connection
  #     Error". nix-ld does not help - the interpreter is Nix's own Python.
  #   - --python: otherwise uv downloads a generic-linux Python, which cannot
  #     execute here at all.
  # ---------------------------------------------------------------------------
  # rhythm - note taker (SUPER+N) and kanban sync
  #
  # DEV LAYOUT: the Python lives in ~/dev/rhythm-note-taker and is deliberately
  # NOT vendored into this flake yet, so an edit takes effect on the next
  # invocation with no rebuild. Nix owns only the interface - the binary name,
  # the PATH closure, the vault path - none of which change when the Python
  # does. To promote it later:
  #     cp -r ~/dev/rhythm-note-taker/src/rhythm ~/nixos-config/scripts/rhythm
  #     git add -A        # untracked files are NOT part of a git: flake source
  # then swap SRC for ${./scripts/rhythm}. That is the whole migration.
  #
  # RHYTHM_VAULT rather than HOME_VAULT: even with the systemd.user
  # .sessionVariables fix below, the value only lands at the next LOGIN, and
  # the tmux server predates it either way. Baking the literal path from
  # env.nix is what makes `rhythm` correct from a keybind today.
  # ---------------------------------------------------------------------------
  rhythm = pkgs.writeShellApplication {
    name = "rhythm";
    # ghostty, neovim and tmux are deliberately ABSENT: adding them would put
    # UNCONFIGURED copies ahead of the home-manager wrappers on PATH, and the
    # overlay would open a default nvim with none of your config.
    runtimeInputs = with pkgs; [ python3 libnotify ];
    text = ''
      SRC="$HOME/dev/rhythm-note-taker/src/rhythm"
      if [ ! -d "$SRC" ]; then
        # A Hyprland bind that execs a missing file fails invisibly, so say so.
        notify-send --urgency=critical "rhythm" "source tree missing: $SRC" || true
        echo "rhythm: source tree missing: $SRC" >&2
        exit 1
      fi
      export RHYTHM_VAULT=${env.HOME_VAULT}
      exec python3 "$SRC" "$@"
    '';
  };

  # The overlay process itself. Never invoked directly - rhythm-toggle execs it
  # through a Hyprland exec-bracket so it inherits HL_INITIAL_WORKSPACE_TOKEN,
  # which is what actually places the window.
  rhythmOverlay = pkgs.writeShellScriptBin "rhythm-overlay" ''
    set -eu
    export RHYTHM_VAULT=${env.HOME_VAULT}

    # HOME_VAULT as well, and deliberately: obsidian.nvim and vault_panel.lua
    # both read it and disable themselves when it is empty, and the "disabled"
    # notice is one of the startup messages that trips nvim's hit-enter prompt,
    # which blocks the main loop and leaves the overlay opening stuck. Setting
    # it here also makes obsidian.nvim work inside the note app immediately,
    # rather than after the next login.
    export HOME_VAULT=${env.HOME_VAULT}

    # `--class` must be a valid GTK application id (dotted reverse-DNS).
    # An invalid one is a SILENT fallback to com.mitchellh.ghostty, which would
    # make every rule and gate keyed on this class hit your ordinary terminals
    # instead. `ghostty +validate-config --class=...` exits 0 and prints
    # nothing, so this cannot be caught at build time. Verify at runtime with:
    #   hyprctl clients -j | jq -r '.[] | select(.class|test("rhythm")) | .class'
    #
    # `-e` forces gtk-single-instance=false, which is what makes --class take
    # effect at all; it also forces quit-after-last-window-closed=true, which
    # is why `:q` is remapped to hide inside lua/rhythm.lua.
    # --font-size applies to this window only; your ordinary terminals keep 12.
    # It must precede -e, because everything after -e is the command. -e is
    # also what makes per-window config flags take effect at all.
    exec ghostty --class=com.rhythm.note --font-size=10 -e \
      nvim --listen "''${XDG_RUNTIME_DIR:-/tmp}/rhythm.sock" \
           -c 'lua require("rhythm").open()'
  '';

  # SUPER+N. Modelled on ai-scratchpad-show, with one difference: this is a
  # real toggle, so an already-visible overlay hides rather than no-opping.
  rhythmToggle = pkgs.writeShellScriptBin "rhythm-toggle" ''
    set -eu
    CLS='com.rhythm.note'

    # Find the window ANYWHERE, not just on its own special workspace -
    # otherwise a drifted window looks like "not running", we relaunch, and a
    # second instance lands in the wrong place.
    addr=$(hyprctl clients -j \
      | jq -r --arg c "$CLS" 'first(.[] | select(.class == $c)) | .address // ""')
    at=$(hyprctl clients -j \
      | jq -r --arg c "$CLS" 'first(.[] | select(.class == $c)) | .workspace.name // ""')

    if [ -n "$addr" ]; then
      if [ "$at" != "special:rhythm" ]; then
        # Drifted - pull it home before revealing.
        hyprctl dispatch movetoworkspacesilent "special:rhythm,address:$addr"
      fi
      # Dispatch the BARE name - the dispatcher prepends "special:" itself.
      hyprctl dispatch togglespecialworkspace rhythm
      exit 0
    fi

    # Not running. Hold a lock across the launch so a double-tapped SUPER+N
    # cannot start a second nvim that dies on "--listen: address already in
    # use" and flashes a window. A stale socket FILE is fine - nvim replaces it.
    exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/rhythm.launch.lock"
    flock -n 9 || exit 0

    # Bracket exec-rules split on ';' (not ','), and attach by PID+token rather
    # than by window class. `size` is a muParser expression over the LOGICAL
    # monitor size - percentages silently no-op. No `silent`: mapping the
    # window opens its special workspace and focuses it, which is what we want.
    hyprctl dispatch exec \
      "[workspace special:rhythm; float; maximize] ${rhythmOverlay}/bin/rhythm-overlay"

    # Hold the lock until the window actually MAPS, not merely until the
    # dispatch returns. Releasing it at exit leaves a gap in which a second
    # SUPER+N still sees no client, takes the freed lock and launches a second
    # overlay. Observed live before this loop existed: two windows and five
    # nvim processes, with the loser dying on "--listen: address already in
    # use". Ghostty maps within a few hundred ms; nvim finishing its plugin
    # load long afterwards does not matter here.
    i=0
    while [ "$i" -lt 50 ]; do
      sleep 0.1
      if hyprctl clients -j | jq -e --arg c "$CLS" 'any(.[]; .class == $c)' >/dev/null 2>&1
      then break
      fi
      i=$((i + 1))
    done
  '';

  # SUPER+C. No-ops unless the rhythm window is focused; the "is the notepad
  # the active view" half is answered inside nvim, in the same tick as the
  # action, because asking then acting from out here is two round trips with a
  # gap in between.
  rhythmNew = pkgs.writeShellScriptBin "rhythm-new" ''
    # Deliberately no `set -e`: every failure path must still exit 0, so a
    # keybind never surfaces an error.
    #
    # `.class // ""` - activewindow returns {} when nothing is focused, and a
    # bare `jq -r .class` would yield the STRING "null".
    cls=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""')
    [ "$cls" = "com.rhythm.note" ] || exit 0

    # --remote-send (nvim_input, a FAST rpc call), never --remote-expr: the
    # latter has no timeout of any kind and hangs indefinitely whenever nvim's
    # main loop is blocked, which on a global keybind is unacceptable.
    # The payload must contain NO literal '<' beyond <Cmd> and <CR>, or the key
    # parser swallows the trailing <CR> and strands nvim on the command line.
    timeout 1 nvim --server "''${XDG_RUNTIME_DIR:-/tmp}/rhythm.sock" \
      --remote-send '<Cmd>lua require("rhythm").new_note()<CR>' >/dev/null 2>&1
    exit 0
  '';

  cgc = pkgs.writeShellApplication {
    name = "cgc";
    runtimeInputs = [ pkgs.uv ];
    text = ''
      export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec uvx --python ${pkgs.python3}/bin/python3 \
        --from codegraphcontext==0.6.13 cgc "$@"
    '';
  };

  aiScratchpadShow = pkgs.writeShellScriptBin "ai-scratchpad-show" ''
    set -eu
    ws="''${1:?usage: ai-scratchpad-show <ai-chatgpt|ai-claude|ai-grok>}"

    # `size` takes a muParser expression in Hyprland 0.56 - percentages
    # silently no-op. monitor_w/monitor_h are the LOGICAL size, so this is
    # scale-correct.
    RULES='float; center; size monitor_w*0.6 monitor_h*0.75'

    # All three AIs are now Chromium --app= web-apps. `prof` is the per-app
    # --user-data-dir, which is what keeps the three logins isolated from one
    # another and from the ordinary browser profile. There is no `bin` and no
    # deep-link branch any more: a Chromium web-app registers no scheme
    # handler, so nothing can hand it an OAuth callback.
    case "$ws" in
      ai-chatgpt) url='https://chatgpt.com'; prof='chatgpt' ;;
      ai-claude)  url='https://claude.ai';   prof='claude' ;;
      ai-grok)    url='https://grok.com';    prof='grok' ;;
      *) echo "unknown scratchpad: $ws" >&2; exit 1 ;;
    esac

    # Chromium derives an app window's app_id from the --app= URL - NOT from
    # --class, which it ignores under Wayland - and appends the PROFILE
    # DIRECTORY basename, which is "Default" inside any --user-data-dir. So a
    # private --user-data-dir does not change the class. Two footguns, both
    # observed live on Hyprland 0.56.2 / Chromium 153: --profile-directory=AI
    # yields chrome-claude.ai__-AI, and a path in the URL becomes part of the
    # id (https://claude.ai/new -> chrome-claude.ai__new-Default). Keep the
    # URLs bare origins and never add --profile-directory.
    host="''${url#https://}"
    host="''${host%%/*}"
    cls="chrome-''${host}__-Default"

    dir="$HOME/.local/share/webapps/$prof"
    cmd="chromium --app=$url --user-data-dir=$dir --no-first-run --no-default-browser-check"

    # Find an existing window for this app ANYWHERE, not just on its own
    # special workspace - otherwise a drifted window looks like "not running",
    # we relaunch, and a second instance lands in the wrong place.
    addr=$(hyprctl clients -j \
      | jq -r --arg c "$cls" 'first(.[] | select(.class == $c)) | .address // ""')
    at=$(hyprctl clients -j \
      | jq -r --arg c "$cls" 'first(.[] | select(.class == $c)) | .workspace.name // ""')
    cur=$(hyprctl monitors -j \
      | jq -r 'first(.[] | select(.focused)) | .specialWorkspace.name // ""')

    if [ -n "$addr" ] && [ "$at" != "special:$ws" ]; then
      # Drifted - pull it home before revealing.
      hyprctl dispatch movetoworkspacesilent "special:$ws,address:$addr"
    fi

    if [ -z "$addr" ]; then
      # Bracket exec-rules split on ';' (not ','), and attach by PID+token
      # rather than window class. No `silent`: mapping the window opens its
      # special workspace and focuses it, which is what we want here.
      mkdir -p "$dir"
      hyprctl dispatch exec "[workspace special:$ws; $RULES] $cmd"
    elif [ "$cur" != "special:$ws" ]; then
      # Dispatch the BARE name - the dispatcher prepends "special:" itself.
      hyprctl dispatch togglespecialworkspace "$ws"
    fi
    # Already visible: do nothing.
  '';
  aiScratchpadToggle = pkgs.writeShellScriptBin "ai-scratchpad-toggle" ''
    set -eu

    # Reports the prefixed name, or "" when no special workspace is open.
    # Do NOT use a window's .visible/.hidden here - all three AI windows report
    # visible=true even when no special workspace is active.
    cur=$(hyprctl monitors -j \
      | jq -r 'first(.[] | select(.focused)) | .specialWorkspace.name // ""')

    # An overlay is up: hide it. Hyprland restores focus to whatever was
    # focused on the underlying workspace.
    case "$cur" in
      special:ai-*)
        hyprctl dispatch togglespecialworkspace "''${cur#special:}"
        exit 0
        ;;
    esac

    # Nothing up: reopen whichever AI app was focused most recently.
    # focusHistoryID is Hyprland's MRU index - 0 is the focused window, larger
    # is longer ago - so the lowest among the three wins. The >= 0 filter is
    # load-bearing: a window missing from the history reports -1, which would
    # otherwise sort first and always win.
    # Keyed on class, not workspace, so a drifted window still maps correctly.
    pick=$(hyprctl clients -j | jq -r '
      [ .[]
        | select(.focusHistoryID >= 0)
        | select(.class == "chrome-chatgpt.com__-Default"
              or .class == "chrome-claude.ai__-Default"
              or .class == "chrome-grok.com__-Default")
      ] | sort_by(.focusHistoryID) | first | .class // ""')

    case "$pick" in
      chrome-chatgpt.com__-Default) ws=ai-chatgpt ;;
      chrome-claude.ai__-Default)   ws=ai-claude ;;
      chrome-grok.com__-Default)    ws=ai-grok ;;
      *)                            ws=ai-chatgpt ;; # none running yet
    esac

    # Absolute store path so this does not depend on PATH.
    exec ${aiScratchpadShow}/bin/ai-scratchpad-show "$ws"
  '';

  aiScratchpadNext = pkgs.writeShellScriptBin "ai-scratchpad-next" ''
    set -eu

    cur=$(hyprctl monitors -j \
      | jq -r 'first(.[] | select(.focused)) | .specialWorkspace.name // ""')

    # The guard: do nothing at all unless an AI overlay is actually up. This is
    # what scopes SUPER+Tab to the overlay. A Hyprland submap would scope it
    # natively, but while a submap is active every bind outside it stops firing
    # - a stuck submap would cost the lock screen and volume keys too.
    # A help sheet is up: rofi has focus, but SUPER+Tab is a COMPOSITOR grab and
    # never reaches it. So hand the next sheet to help-sheet's loop and close
    # the current popup. Plain Tab is the smoother path - rofi sees that one
    # directly and exits with code 10, no kill and no flash.
    state="''${XDG_RUNTIME_DIR:-/tmp}/help-sheet.current"
    if [ -f "$state" ]; then
      # Same rotation as next_sheet() in scripts/help-sheet.sh.
      case "$(cat "$state")" in
        hypr) echo nvim ;;
        nvim) echo tmux ;;
        tmux) echo ghostty ;;
        *)    echo hypr ;;
      esac > "''${XDG_RUNTIME_DIR:-/tmp}/help-sheet.next"
      pkill -x rofi || true
      exit 0
    fi

    case "$cur" in
      special:ai-chatgpt) next=ai-claude ;;
      special:ai-claude)  next=ai-grok ;;
      special:ai-grok)    next=ai-chatgpt ;; # wrap
      *) exit 0 ;;
    esac

    # Delegate to `show`, never dispatch togglespecialworkspace directly:
    # special workspaces are destroyed when they empty, so Tabbing to an app
    # that was never launched would otherwise reveal a blank overlay. Only
    # `show` has the launch-if-absent path.
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
  # Only .local/bin survives: `uv tool install` targets it. The other three
  # ($HOME/tools/bin, .npm-packages/bin, .grok/bin) were pre-Nix leftovers
  # pointing at directories that do not exist - standing invitations for an
  # imperative install that would vanish on another machine. .npm-packages/bin
  # in particular can never be populated: npm's prefix is a read-only store
  # path, so `npm -g` always fails here.
  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # Edit the values in env.nix, not here.
  home.sessionVariables = env;

  # The same values for the systemd user manager, which does NOT read
  # hm-session-vars.sh. This is what writes them into
  # ~/.config/environment.d/10-home-manager.conf, and so into every user unit
  # and everything Hyprland execs.
  #
  # It also cures a subtler failure: hm-session-vars.sh returns early when
  # __HM_SESS_VARS_SOURCED is already set, and the running session and tmux
  # server both export it from a generation that predates env.nix - so
  # $HOME_VAULT is currently unset even in a fresh login shell, which is why
  # obsidian.nvim and vault_panel.lua are both inert.
  #
  # environment.d is read once, when `systemd --user` starts: this takes
  # effect at the next LOGIN, not at the next rebuild.
  systemd.user.sessionVariables = env;

  # ---------------------------------------------------------------------------
  # General packages
  # ---------------------------------------------------------------------------

  home.packages = with pkgs; [
    # Agents
    claude-code
    cgc # for the cgc-refresh skill - see the wrapper in the let block

    # All three AI apps are Chromium web-apps with isolated --user-data-dir
    # profiles - see the ai-scratchpad-show script above.
    chromium

    # Desktop applications
    obsidian

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
    helpSheet
    rhythm
    rhythmOverlay
    rhythmToggle
    rhythmNew
    aiScratchpadShow
    aiScratchpadToggle
    aiScratchpadNext

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
    # matplotlib + mplcursors are for the picklable-plots Claude skill's
    # show_figure.py viewer (TkAgg backend). They have to come from Nix: pip
    # wheels of matplotlib link libstdc++, which a NixOS venv cannot find.
    (python3.withPackages (ps: [ ps.matplotlib ps.mplcursors ]))
    nodejs

    # Shell and Nix tools
    shellcheck
    shfmt
    nixfmt
    nil

    # Language servers. These replace the copies mason downloaded into
    # ~/.local/share/nvim/mason, which are generic-linux ELF binaries and
    # cannot execute on NixOS at all.
    lua-language-server
    harper # provides harper-ls
    pyright
    vscode-langservers-extracted # html / css / json / eslint

    # Formatters and linters
    prettier
    stylua
    ruff

    # Python. uv rather than pip: per-project, lockfile-based environments,
    # with no ~/.local/lib state to lose on a rebuild. Note bare `python3`
    # ships no pip at all, and python3Full was removed from nixpkgs.
    uv

    # Rust. Required for avante.nvim's `make` build step, which has silently
    # never produced its native library.
    cargo
    rustc

    # JS runtimes and tooling (npm and npx already ship inside `nodejs`)
    typescript
    pnpm
    bun
    deno
  ];

  fonts.fontconfig.enable = true;

  # Wallpaper lives in the repo, so a fresh machine gets it from the flake.

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
  # Claude Code
  # ---------------------------------------------------------------------------

  # Individual files only - never ~/.claude itself, which Claude Code writes
  # to constantly (credentials, history, projects, settings.json). These land
  # as read-only store symlinks, so edit the dotfiles, not ~/.claude: /memory
  # cannot save changes to CLAUDE.md.
  home.file = {
    ".claude/CLAUDE.md".text = substEnv ./dotfiles/claude/.claude/CLAUDE.md;

    ".claude/skills/cgc-refresh" = {
      source = ./dotfiles/claude/.claude/skills/cgc-refresh;
      recursive = true;
    };
    ".claude/skills/picklable-plots" = {
      source = ./dotfiles/claude/.claude/skills/picklable-plots;
      recursive = true;
    };

    ".claude/skills/session-notes/SKILL.md".text =
      substEnv ./dotfiles/claude/.claude/skills/session-notes/SKILL.md;
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

  # Restores the daemon that was lost when an over-broad edit to
  # xdg.desktopEntries swallowed this block in 73bd28c.
  services.hyprpaper = {
    enable = true;

    settings = {
      splash = false;

      # Load-bearing: wallpaper-rotate sets the image over IPC. hyprpaper
      # 0.8.4's IPC is down to just `wallpaper` and `listactive` - preload,
      # unload, listloaded and reload were all removed with the old protocol.
      ipc = "on";

      # Deliberately NO `wallpaper` entry: wallpaper-rotate below is the single
      # source of truth for which image is shown. Declaring one here would mean
      # two places decide, and it would flash past on every login.
    };
  };

  systemd.user.services.wallpaper-rotate = {
    Unit = {
      Description = "Advance the wallpaper one step per session";
      ConditionEnvironment = "WAYLAND_DISPLAY";
      After = [ "graphical-session.target" "hyprpaper.service" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaperRotate}";
    };

    # Unlike a timer, this one DOES install into the target - running once at
    # session start is the whole point.
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ---------------------------------------------------------------------------
  # Hourly nudge for kanban "Route" tasks - the column for things that need
  # passing along to someone - 11:00 to 14:00 local, weekdays.
  # ---------------------------------------------------------------------------
  systemd.user.services.rhythm-route = {
    Unit = {
      Description = "Notify about kanban Route tasks";
      # NOT ConditionEnvironment=WAYLAND_DISPLAY, despite the precedent above:
      # uwsm's env_cleanup.list does not include WAYLAND_DISPLAY, so it lingers
      # stale in the user manager after the compositor exits and the condition
      # would pass with nothing to notify. HYPRLAND_INSTANCE_SIGNATURE IS in
      # that list, so it is the honest probe for "is there a session".
      ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${rhythm}/bin/rhythm remind-route";
    };

    # Deliberately NO Install: the timer is what starts this. Installing it
    # into a target would also fire it once at every login.
  };

  # ---------------------------------------------------------------------------
  # Fold every note's markers onto the board every half hour, so the board is
  # right even when the app has not been opened. The in-app BufWritePost hook
  # covers the note you are writing; this covers everything else, and it passes
  # no --cursor, so it also sweeps up any line a cursor-skip left unstamped.
  # ---------------------------------------------------------------------------
  systemd.user.services.rhythm-refresh = {
    Unit.Description = "Fold note markers onto the kanban board";
    Service = {
      Type = "oneshot";
      ExecStart = "${rhythm}/bin/rhythm sync";
    };
    # No ConditionEnvironment: this touches files, not the display, so it is
    # useful with or without a graphical session.
  };

  systemd.user.timers.rhythm-refresh = {
    Unit.Description = "Half-hourly kanban sync";
    Timer = {
      OnCalendar = "*:0/30";
      # Catch up one missed run after a resume, rather than silently skipping
      # the sweep. Unlike the Route nudge, a late sync is still correct.
      Persistent = true;
      RandomizedDelaySec = "30s";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.timers.rhythm-route = {
    Unit = {
      Description = "Hourly kanban Route reminder, 11:00-14:00 on weekdays";
      PartOf = [ "graphical-session.target" ];
    };

    Timer = {
      # Local time. America/Phoenix never observes DST, so there is no skipped
      # or doubled hour to reason about. Verify with:
      #   systemd-analyze calendar 'Mon..Fri *-*-* 11,12,13,14:00:00'
      OnCalendar = "Mon..Fri *-*-* 11,12,13,14:00:00";

      # The default AccuracySec is 1min, which would let a nudge drift off the
      # hour it is named after.
      AccuracySec = "1s";

      # Persistent is for catching up a missed backup. A time-of-day nudge
      # fired at 16:30 for the 11:00 slot is just noise, and it would also fire
      # immediately the first time the timer starts.
      Persistent = false;
    };

    # graphical-session.target, not timers.target: the nudge only means
    # anything while you are logged in, and it should stop on logout.
    Install.WantedBy = [ "graphical-session.target" ];
  };

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

  # ---------------------------------------------------------------------------
  # Launcher icons for the three AI web-apps
  #
  # The old `icon = "chatgpt"` / `icon = "claude-desktop"` names resolved only
  # through the two flake packages that are now gone, so the icons are vendored
  # in-repo instead.
  #
  # $XDG_DATA_HOME/icons is the FIRST entry in the icon-theme search path of
  # every consumer here - GTK3/waybar, rofi (its vendored libnkutils calls
  # try_dir(g_get_user_data_dir()) before anything else) and fuzzel - so these
  # win over anything a package ships under the same name.
  #
  # No index.theme is needed here and no gtk-update-icon-cache step: the
  # loaders read hicolor's index.theme from the first base dir that has one
  # (the HM profile and /run/current-system/sw both do), then look for the
  # subdirectories it lists in EVERY base dir, falling back to a directory scan
  # when no cache is present. home-manager never generates a cache.
  #
  # Each PNG goes in the hicolor dir matching its real pixel size - claude is
  # 256x256, grok is 32x32. chatgpt's art is 1024x1024, but hicolor's
  # index.theme declares apps dirs only up to 512x512, so a 1024x1024 dir would
  # never be searched.
  # ---------------------------------------------------------------------------
  xdg.dataFile = {
    "icons/hicolor/256x256/apps/claude.png".source = ./icons/claude.png;
    "icons/hicolor/512x512/apps/chatgpt.png".source = ./icons/chatgpt.png;
    "icons/hicolor/32x32/apps/grok.png".source = ./icons/grok.png;
  };

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "text/html" = "firefox.desktop";

      # The claude:// and codex:// handlers are gone with the Electron apps -
      # a Chromium --app= window cannot service them.
      #
      # claude-cli:// stays: the Claude Code CLI writes that handler itself
      # into ~/.local/share/applications/claude-code-url-handler.desktop (a
      # real file the CLI owns, not a store symlink), so it is unrelated to the
      # removed desktop packages.
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

  # ---------------------------------------------------------------------------
  # Launcher entries for the three AI apps
  #
  # Each entry routes through ai-scratchpad-show so rofi and SUPER+G behave
  # identically: launching the app binary directly would leave the window
  # parked on a hidden special workspace and nothing would appear.
  #
  # home-manager installs these into the HM PROFILE
  # (/etc/profiles/per-user/pretamc/share/applications, because
  # home-manager.useUserPackages = true) - NOT into $XDG_DATA_HOME - and they
  # win over any package-supplied entry of the same ID through lib.hiPrio
  # inside that one buildEnv.
  #
  # StartupWMClass values are the live Wayland app_ids, observed with hyprctl
  # clients on Hyprland 0.56.2 / Chromium 153. They are derived from the --app=
  # URL, not from --class.
  #
  # No mimeType and no %U: these are web-apps now, with no scheme handler to
  # advertise. Declaring one would put a dead OAuth route back into
  # mimeinfo.cache.
  # ---------------------------------------------------------------------------

  xdg.desktopEntries = {
    chatgpt = {
      name = "ChatGPT";
      genericName = "AI assistant";
      comment = "ChatGPT by OpenAI";
      icon = "chatgpt";
      exec = "ai-scratchpad-show ai-chatgpt";
      type = "Application";
      terminal = false;
      categories = [ "Utility" "Development" ];
      settings.StartupWMClass = "chrome-chatgpt.com__-Default";
    };

    claude = {
      name = "Claude";
      genericName = "AI assistant";
      comment = "Claude by Anthropic";
      icon = "claude";
      exec = "ai-scratchpad-show ai-claude";
      type = "Application";
      terminal = false;
      categories = [ "Utility" "Development" ];
      settings.StartupWMClass = "chrome-claude.ai__-Default";
    };

    grok = {
      name = "Grok";
      genericName = "AI assistant";
      comment = "Grok by xAI";
      icon = "grok";
      exec = "ai-scratchpad-show ai-grok";
      type = "Application";
      terminal = false;
      categories = [ "Utility" ];
      settings.StartupWMClass = "chrome-grok.com__-Default";
    };
  };
}
