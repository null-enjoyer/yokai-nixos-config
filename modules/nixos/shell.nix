{ pkgs, lib, ... }:

# Keep the post-init block after Oh My Zsh, autosuggestions and Atuin hooks.
lib.mkMerge [
{
  programs.zsh = {
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    autosuggestions = {
      enable = true;
      strategy = [ "history" "completion" ];
      highlightStyle = "fg=244";
    };

    histSize = 100000;
    setOptions = [
      "HIST_IGNORE_ALL_DUPS"  # a re-run command moves to the front instead of piling up
      "HIST_IGNORE_SPACE"     # leading space = don't record (secrets, throwaway lines)
      "HIST_REDUCE_BLANKS"    # normalise whitespace so near-identical lines dedupe
      "EXTENDED_HISTORY"      # record timestamps + duration
      "SHARE_HISTORY"         # live-share history across open terminals
      "HIST_FCNTL_LOCK"       # (module default) safe concurrent writes to the histfile
    ];

    shellAliases = {
      ll = "ls -lah";
      ".." = "cd ..";
      gs = "git status";
      gd = "git diff";
      v = "nvim";
      f = "spf";
    };

    ohMyZsh = {
      enable = true;
      plugins = [ "git" "sudo" "history" ];
    };

    promptInit = ''
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi
    '';

    interactiveShellInit = ''
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

      command -v direnv >/dev/null && eval "$(direnv hook zsh)"

      command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

      command -v fzf >/dev/null && source <(fzf --zsh)

      export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"

      source ${../../config/superfile/shell.zsh}

      br() {
        local cmd_file cmd
        cmd_file="$(mktemp)"
        if broot --outcmd "$cmd_file" "''${@:-$PWD}"; then
          cmd="$(< "$cmd_file")"
          rm -f -- "$cmd_file"
          [[ -n "$cmd" ]] && eval "$cmd"
        else
          rm -f -- "$cmd_file"
        fi
      }
      bindkey -s '^o' 'br\n'
    '';
  };

  programs.atuin = {
    flags = [ "--disable-up-arrow" ];
    daemon.enable = false;
    settings = {
      auto_sync = false;
      update_check = false;      # Managed by Nix.
      style = "compact";         # draw inline under the prompt instead of a fullscreen TUI
      inline_height = 20;
      search_mode = "fuzzy";
      filter_mode = "global";    # Ctrl+R searches everything; Ctrl+R again cycles filters
      enter_accept = false;      # Enter puts the command on the line to edit, not run it
    };
  };

  environment.sessionVariables.TERMINAL = "ghostty";

  environment.sessionVariables.EDITOR = "nvim";
  environment.sessionVariables.VISUAL = "nvim";

  environment.localBinInPath = true;
}
{
  programs.zsh.interactiveShellInit = lib.mkAfter ''
    # Suggestions must match the current prefix to render after the cursor.
    _zsh_autosuggest_strategy_atuin() {
      typeset -g suggestion
      local -a opts=( --cmd-only --limit 1 --search-mode prefix )
      suggestion=$(atuin search $opts --filter-mode directory -- "$1" 2>/dev/null | tail -n 1)
      [[ -z $suggestion ]] && \
        suggestion=$(atuin search $opts --filter-mode global -- "$1" 2>/dev/null | tail -n 1)
    }
    # The NixOS strategy option only accepts the built-in strategies.
    ZSH_AUTOSUGGEST_STRATEGY=(atuin history completion)

    bindkey '^[[1;5C' forward-word

    (( $+widgets[atuin-search] )) && bindkey '^r' atuin-search

    zstyle ':completion:*' menu select
    zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'

    _tab_or_broot() {
      if [[ -z $BUFFER ]]; then
        zle -I
        br
        zle reset-prompt
      else
        zle expand-or-complete
      fi
    }
    zle -N _tab_or_broot
    bindkey '^I' _tab_or_broot
  '';
}
]
