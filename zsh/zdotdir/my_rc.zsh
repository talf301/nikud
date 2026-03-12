# *** PROMPT ***

# To get beam shaped cursor on instant prompt startup
echo -ne '\e[5 q'

# Enable Powerlevel10k instant prompt. Should stay close to the top of this rc file
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Source powerlevel10k
. "${ZDOTDIR:h}/powerlevel10k/powerlevel10k.zsh-theme"

# To customize prompt, run `p10k configure` or edit $ZDOTDIR/.p10k.zsh.
[[ ! -f "${ZDOTDIR}/.p10k.zsh" ]] || source "${ZDOTDIR}/.p10k.zsh"

eval "$(atuin init zsh --disable-ctrl-r --disable-up-arrow)"

# *** ALIASES ***
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first --git'
alias less='bat --paging always'
alias cat='bat'
export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | bat -p -lman'"
alias mm='micromamba'

alias vi=vim
alias vim=nvim

alias hist-dur='history -iD 0 | fzf'

# Handy reference, courtesy of https://github.com/seebi/dircolors-solarized
# SOLARIZED HEX     16/8 TERMCOL  XTERM/HEX   L*A*B      sRGB        HSB
# --------- ------- ---- -------  ----------- ---------- ----------- -----------
# base03    #002b36  8/4 brblack  234 #1c1c1c 15 -12 -12   0  43  54 193 100  21
# base02    #073642  0/4 black    235 #262626 20 -12 -12   7  54  66 192  90  26
# base01    #586e75 10/7 brgreen  240 #4e4e4e 45 -07 -07  88 110 117 194  25  46
# base00    #657b83 11/7 bryellow 241 #585858 50 -07 -07 101 123 131 195  23  51
# base0     #839496 12/6 brblue   244 #808080 60 -06 -03 131 148 150 186  13  59
# base1     #93a1a1 14/4 brcyan   245 #8a8a8a 65 -05 -02 147 161 161 180   9  63
# base2     #eee8d5  7/7 white    254 #d7d7af 92 -00  10 238 232 213  44  11  93
# base3     #fdf6e3 15/7 brwhite  230 #ffffd7 97  00  10 253 246 227  44  10  99
# yellow    #b58900  3/3 yellow   136 #af8700 60  10  65 181 137   0  45 100  71
# orange    #cb4b16  9/3 brred    166 #d75f00 50  50  55 203  75  22  18  89  80
# red       #dc322f  1/1 red      160 #d70000 50  65  45 220  50  47   1  79  86
# magenta   #d33682  5/5 magenta  125 #af005f 50  65 -05 211  54 130 331  74  83
# violet    #6c71c4 13/5 brmagenta 61 #5f5faf 50  15 -45 108 113 196 237  45  77
# blue      #268bd2  4/4 blue      33 #0087ff 55 -10 -45  38 139 210 205  82  82
# cyan      #2aa198  6/6 cyan      37 #00afaf 60 -35 -05  42 161 152 175  74  63
# green     #859900  2/2 green     64 #5f8700 60 -20  65 133 153   0  68 100  60

# Usage: palette
palette() {
    local -a colors
    for i in {000..16}; do
        colors+=("%F{$i}hello: $i%f")
    done
    print -cP $colors
}

# Usage: printc COLOR_CODE
printc() {
    local color="%F{$1}"
    echo -E ${(qqqq)${(%)color}}
}

# Safe ops. Ask the user before doing anything destructive.
alias cp='cp -i'
alias ln='ln -i'
alias mv='mv -i'
alias rm='rm -i'

alias rsync='rsync -avzPu --no-i-r --info=progress2'

lazygit() {
  __get_vscode_ipc__
  if [[ $VSCODE_IPC_HOOK_CLI != "" ]]; then
    VISUAL=code command lazygit "$@"
  else
    command lazygit "$@"
  fi
}

# utility function; edit with whatever is appropriate - vscode or vim
e() {
  __get_vscode_ipc__
  if [[ $VSCODE_IPC_HOOK_CLI != "" ]]; then
    command code "$@"
  else
    $VISUAL "$@"
  fi
}

# suffix aliases!
# utility function; open script files for editing if not executable, otherwise execute
__exec_or_edit() {
    if [[ -x $1 ]]; then
        "$@"
    else
        e "$1"
    fi
}
alias -s {sh,zsh,py}=__exec_or_edit
alias -s {txt,json,ini,toml,yml,yaml,xml,html,md,lock,snap,rst,cpp,h,rs}=e
alias -s {log,csv}=bat
alias -s git='git clone'
alias -s o='nm --demangle'
alias -s so='ldd'

edit_output() {
  file=`mktemp`.sh
  tmux capture-pane -p > $file
  e $file
}

# For better vi usability, reduce key delay/timeout
KEYTIMEOUT=1

# Utility function to reduce repetition when binding widgets
function widget-and-bind() {
  local widget_name=${@[-1]}
  builtin zle -N $widget_name
  builtin bindkey "$@"
}

# Edit command in full blown vim; bound to normal mode C-e
autoload -Uz edit-command-line
widget-and-bind -M vicmd "^E" edit-command-line

# Support for GUI clipboard
source $ZDOTDIR/clipboard.zsh

# We want to call this before sourcing ignore/host specific file in case they want to
# activate environments
eval "$(micromamba shell hook --shell zsh)"

# A separate file that gets sourced; convenient for putting things you may not want to upstream
maybe_source $ZDOTDIR/ignore_rc.zsh

# A per host file that optionally gets sourced
maybe_source $ZDOTDIR/host_$(hostname)_rc.zsh

# recent directories
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs
zstyle ':chpwd:*' recent-dirs-max 1000

# Intuitive back-forward navigation, similar to a browser.
# Also provides up (cd ..), and down (fzf recursive dir search).
# Bound to Ctrl-hjkl
# https://www.reddit.com/r/zsh/comments/ka4sae/navigate_folder_history_like_in_fish/
function my-redraw-prompt() {
  {
    builtin echoti civis
    builtin local f
    for f in chpwd "${chpwd_functions[@]}" precmd "${precmd_functions[@]}"; do
      (( ! ${+functions[$f]} )) || "$f" &>/dev/null || builtin true
    done
    builtin zle reset-prompt
  } always {
    builtin echoti cnorm
  }
}

function my-cd-rotate() {
  () {
    builtin emulate -L zsh
    while (( $#dirstack )) && ! builtin pushd -q $1 &>/dev/null; do
      builtin popd -q $1
    done
    (( $#dirstack ))
  } "$@" && my-redraw-prompt
}

function my-cd-up()      { builtin cd -q .. && my-redraw-prompt; }
function my-cd-back()    { my-cd-rotate +1; }
function my-cd-forward() { my-cd-rotate -0; }

# Wait to bind these functions until fzf functionality has loaded

unsetopt LIST_BEEP

# From prezto
# zpreztorc
autoload zmv
autoload zargs

# environment
setopt COMBINING_CHARS      # Combine zero-length punctuation characters (accents) with the base character.
setopt INTERACTIVE_COMMENTS # Enable comments in interactive shell.
setopt RC_QUOTES            # Allow 'Henry''s Garage' instead of 'Henry'\''s Garage'.
unsetopt MAIL_WARNING       # Don't print a warning message if a mail file has been accessed.
setopt printexitvalue       # useful to get more info on errors

# Allow mapping Ctrl+S and Ctrl+Q shortcuts
[[ -r ${TTY:-} && -w ${TTY:-} && $+commands[stty] == 1 ]] && stty -ixon <$TTY >$TTY

#
# Jobs
#
setopt LONG_LIST_JOBS     # List jobs in the long format by default.
setopt NOTIFY             # Report status of background jobs immediately.
setopt AUTO_RESUME        # Attempt to resume existing job before creating a new process.
unsetopt BG_NICE          # Don't run all background jobs at a lower priority.
unsetopt HUP              # Don't kill jobs on shell exit.
unsetopt CHECK_JOBS       # Don't report on jobs when shell exits.

# editor
# by default backspace is vi-delete-char which has some pretty funky behavior
bindkey "^?" backward-delete-char

# Home and End seem to do weird, terminal dependent things
# the binding below tested with vscode terminal emulator and windows terminal emulator
bindkey -v "^[[1~" beginning-of-line
bindkey -a "^[[1~" beginning-of-line
bindkey -M viopp "^[[1~" beginning-of-line
bindkey -M visual "^[[1~" beginning-of-line

bindkey -v "^[[4~" end-of-line
bindkey -a "^[[4~" end-of-line
bindkey -M viopp "^[[4~" end-of-line
bindkey -M visual "^[[4~" end-of-line

# history
setopt BANG_HIST                 # Treat the '!' character specially during expansion.
setopt EXTENDED_HISTORY          # Write the history file in the ':start:elapsed;command' format.
setopt SHARE_HISTORY             # Share history between all sessions.
setopt HIST_EXPIRE_DUPS_FIRST    # Expire a duplicate event first when trimming history.
setopt HIST_IGNORE_DUPS          # Do not record an event that was just recorded again.
setopt HIST_IGNORE_ALL_DUPS      # Delete an old recorded event if a new event is a duplicate.
setopt HIST_FIND_NO_DUPS         # Do not display a previously found event.
setopt HIST_IGNORE_SPACE         # Do not record an event starting with a space.
setopt HIST_SAVE_NO_DUPS         # Do not write a duplicate event to the history file.
setopt HIST_VERIFY               # Do not execute immediately upon history expansion.
setopt HIST_BEEP                 # Beep when accessing non-existent history.

HISTFILE="${ZDOTDIR}/.zsh_history"  # The path to the history file.
HISTSIZE=10000  # The maximum number of events to save in the internal history.
SAVEHIST=10000  # The maximum number of events to save in the history file.

# directory
setopt AUTO_CD              # Allows ~nikud
setopt AUTO_PUSHD           # Push the old directory onto the stack on cd. Needed for my-cd-rotate
setopt PUSHD_SILENT         # Do not print the directory stack after pushd or popd.
setopt PUSHD_TO_HOME        # Push to home directory when no argument is given.
setopt CDABLE_VARS          # Allows cd nikud instead of cd ~nikud
setopt MULTIOS              # Write to multiple descriptors.
setopt EXTENDED_GLOB        # Use extended globbing syntax.
unsetopt CLOBBER            # Do not overwrite existing files with > and >>.
                            # Use >! and >>! to bypass.


# *** COMPLETION ***
# Add completions dir
fpath=($ZDOTDIR/completions $fpath)
autoload -Uz compinit
compinit

zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path "${ZDOTDIR}/.zcompcache"

# We avoid completing user because it's VERY expensive on some setups (and not very useful)
zstyle ':completion:*:*:*:users' users

# fzf-tab recommendations
# disable sort when completing `git checkout`
# could consider extending this to other things; presumably this is because sort gets in the way
# of fzf's async nature
zstyle ':completion:*:git-checkout:*' sort false
# set descriptions format to enable group support
zstyle ':completion:*:descriptions' format '[%d]'

# Note the order - fzf.zsh also handles fzf-tab - which must be loaded after compinit, but
# before autosuggestions and syntax highlighting
source "$ZDOTDIR/fzf.zsh"

# bind keys now that fzf is loaded
widget-and-bind -v '^K' my-cd-up
widget-and-bind -v '^H' my-cd-back
widget-and-bind -v '^L' my-cd-forward

widget-and-bind -v '^J' fzf-cd-widget
widget-and-bind -v '^T' fzf-file-widget
widget-and-bind -v '^R' fzf-history-widget
widget-and-bind -v '^S' fzf-rg-widget
widget-and-bind -M vicmd 's' fzf-rg-widget

# Change cursor shape for different vi modes.
# https://unix.stackexchange.com/questions/433273/changing-cursor-style-based-on-mode-in-both-zsh-and-vim
# https://github.com/romkatv/powerlevel10k/issues/2151
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    >$TTY echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    >$TTY echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    >$TTY echo -ne "\e[5 q"
}
zle -N zle-line-init
preexec() {
    >$TTY echo -ne '\e[5 q' ;
} # Use beam shape cursor for each new prompt.

# ~~~THEME
. "${ZDOTDIR:h}/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
fast-theme -q "${XDG_CONFIG_HOME}/fsh/fast-syntax-solarized.ini"

. "${ZDOTDIR:h}/zsh-autosuggestions/zsh-autosuggestions.zsh"
bindkey '^ ' autosuggest-accept
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=14"
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
export ZSH_AUTOSUGGEST_MANUAL_REBIND=1

source ${ZDOTDIR}/color_history.zsh

# If running inside tmux, add a zsh hook on change directory to update tmux's status line
if [[ -n "$TMUX" ]]; then
  function __tmux_update_current_path() {
    tmux refresh-client -S
  }
  add-zsh-hook chpwd __tmux_update_current_path
fi
