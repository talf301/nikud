#!/bin/sh
# Peek: list agent panes (most urgent first) with a live preview of each pane's
# last lines, and answer it, without leaving the current tab.
#   1-9     answer: if the pane shows a dialog, pick option N; otherwise send
#           "N" as a line (for numbered next steps). An option that grants
#           something for later ("always allow") needs the same digit twice.
#           A digit answers only the dialog the preview shows; if the pane has
#           moved on since, nothing is sent and the header says to look again.
#   ctrl-t  type a line and send it to the pane
#   enter   go to the pane and mark it seen
#   ctrl-s  mark it seen and stay
#   esc     close
# Digits answer, so typing filters on letters only. After an answer the list
# reloads with the cursor on the top row, the most urgent pane left; the
# result or rexboard's refusal shows in the header.
# Run by the rexboard_peek action.
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
# fzf runs its preview through $SHELL; zsh takes ~0.6s to start here, sh takes none.
export SHELL=/bin/sh

self=$HOME/.config/rex/peek.sh
if [ "$1" = --rows ]; then
  # key, then coloured columns: state, harness, where, message.
  rexboard ls --json | jq -r '
    def c(n): "\u001b[" + n + "m" + . + "\u001b[0m";
    .[] | [
      .key,
      (.group | if . == "needs_you" then c("1;33") elif . == "working" then c("32") else c("2") end),
      (.harness | sub("-code$"; "") | if . == "claude" then c("38;5;208") else c("36") end),
      ((.session + " › " + .tab) | c("1")),
      ((.msg // .title // "") | c("2"))
    ] | @tsv'
  exit
fi
# The other modes run inside fzf and keep their state in the peek's $PEEK_DIR.
[ $# -eq 0 ] || [ -d "$PEEK_DIR" ] || exit 1
if [ "$1" = --preview ]; then
  # The pane as it looks, colours included, under a three-line heading (pinned
  # by the preview window): where and state, the message, and what each digit
  # sends. The heading, the digits and the dialog ID the answer keys send to all
  # come from one `rexboard show` read, taken before the capture; the ID is
  # recorded in $PEEK_DIR/shown once the preview is drawn, so a digit answers
  # only the dialog shown here.
  key=$2
  rm -f "$PEEK_DIR/shown"
  card=$(rexboard show --json "$key") || { echo "no such pane"; exit; }
  printf '%s' "$card" | jq -r '
    def oneline: gsub("[\r\n\t]+"; " ");
    def cut(n): if length > n then .[0:n-1] + "…" else . end;
    "\u001b[1;7m " + .where + " \u001b[0m  \u001b[1;33m" + .state +
    "\u001b[0m  \u001b[36m" + .harness + "\u001b[0m\n\u001b[1m" +
    ((.msg // .title // "") | oneline) + "\u001b[0m\n\u001b[33m" +
    (if (.options | length) > 0 then
      [.options[] | "\(.digit) " + (.label | oneline | cut(28)) +
        (if .lasting then " (x2)" else "" end)] | join(" · ")
    else "1-9 send the digit as a line" end) + "\u001b[0m"'
  # The capture skips blank cells with cursor-forward codes, which fzf does not
  # draw; turn them into spaces.
  rex capture -s "$(printf '%s' "$card" | jq -r .session_id)" -b "${key#*/}" --trim --format=vt |
    tail -n 80 | perl -pe 's/\e\[(\d*)C/" " x ($1 || 1)/ge; s/\r//g'
  # "-" stands for "no dialog": read with IFS=tab would merge an empty field
  # with its neighbour, since tab is IFS whitespace.
  printf '%s' "$card" | jq -r --arg k "$key" \
    '[$k, (.dialog // "" | if . == "" then "-" else . end), (.options | length)] | @tsv' \
    >"$PEEK_DIR/shown.$$" && mv -f "$PEEK_DIR/shown.$$" "$PEEK_DIR/shown"
  exit
fi
header='1-9: answer · ctrl-t: reply · enter: go · ctrl-s: seen · esc: close'
if [ "$1" = --header ]; then
  # The header, plus the last answer's result on a second line.
  printf '%s\n%s' "$header" "$(cat "$PEEK_DIR/msg" 2>/dev/null)"
  exit
fi
if [ "$1" = --answer ] || [ "$1" = --reply ]; then
  # --answer KEY N: pick option N of a dialog, or send N as a line.
  # --reply KEY: read a line from the terminal and send it.
  # Both answer the dialog the preview showed ($PEEK_DIR/shown), never a newer
  # one: if the pane has moved on, nothing is sent and the header says so.
  # The header records where an answer went, never a reply's text.
  mode=$1 key=$2 n=$3
  : >"$PEEK_DIR/msg"
  [ -n "$key" ] || exit 0
  skey='' dialog='' nopts=''
  IFS='	' read -r skey dialog nopts <"$PEEK_DIR/shown" 2>/dev/null
  [ "$dialog" = - ] && dialog=''
  if [ "$skey" != "$key" ]; then
    echo "the preview is not drawn yet; look again" >"$PEEK_DIR/msg"; exit 0
  fi
  card=$(rexboard show --json "$key") || { echo "no such pane" >"$PEEK_DIR/msg"; exit 0; }
  where=$(printf '%s' "$card" | jq -r '.where')
  if [ "$(printf '%s' "$card" | jq -r '.dialog // ""')" != "$dialog" ]; then
    rm -f "$PEEK_DIR/confirm"
    echo "the dialog changed; look again" >"$PEEK_DIR/msg"; exit 0
  fi
  if [ "$mode" = --reply ]; then
    printf '\n  reply to %s (empty cancels): ' "$where" >/dev/tty
    IFS= read -r text </dev/tty
    [ -n "$text" ] || exit 0
    set -- --text "$text"
    sent="reply sent to $where"
  elif [ "${nopts:-0}" -gt 0 ]; then
    # A second press of the same digit on the same dialog confirms a lasting option.
    set -- --pick "$n"
    [ "$(cat "$PEEK_DIR/confirm" 2>/dev/null)" = "$key $dialog $n" ] && set -- "$@" --confirm
    sent="picked option $n in $where"
  else
    set -- --text "$n"
    sent="sent $n to $where"
  fi
  rm -f "$PEEK_DIR/confirm"
  if out=$(rexboard answer "$key" --dialog "$dialog" "$@" 2>&1); then
    echo "$sent" >"$PEEK_DIR/msg"
    # Wait (at most 3s) for the board to see the answer, so the reload drops the row.
    i=0
    while [ $i -lt 15 ] &&
      [ "$(rexboard show --json "$key" | jq -r '.dialog // ""')" = "$dialog" ]; do
      sleep 0.2; i=$((i + 1))
    done
  elif [ "$mode" = --reply ]; then
    # Never show rexboard's output for a reply: it may echo part of the text.
    echo "the reply was not sent to $where" >"$PEEK_DIR/msg"
  else
    case $out in
      *--confirm*) echo "$key $dialog $n" >"$PEEK_DIR/confirm"
        echo "option $n grants something for later: press $n again to send it" >"$PEEK_DIR/msg" ;;
      *) printf '%s\n' "$out" | head -n1 | sed 's/^error: //' >"$PEEK_DIR/msg" ;;
    esac
  fi
  exit
fi

# mktemp -d makes the directory mode 700; it goes on exit and on a signal.
PEEK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rex-peek.XXXXXX") || exit 1
chmod 700 "$PEEK_DIR"
export PEEK_DIR
trap 'rm -rf "$PEEK_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
after="+transform-header($self --header)+reload($self --rows)+refresh-preview"
set --
for n in 1 2 3 4 5 6 7 8 9; do
  set -- "$@" "--bind=$n:execute-silent($self --answer {1} $n)$after"
done

key=$("$self" --rows | fzf \
  --ansi --delimiter='\t' --with-nth=2.. --no-sort --layout=reverse \
  --header="$header" \
  --color='header:italic:dim,pointer:yellow,hl:yellow,hl+:yellow' \
  --preview="$self --preview {1}" \
  --preview-window='down,75%,follow,border-top,~3' \
  --bind="ctrl-s:execute-silent(rexboard seen {1})+change-header($header)+reload($self --rows)" \
  --bind="ctrl-t:execute($self --reply {1})$after" \
  --bind='load:first' \
  "$@" |
  cut -f1)

# Esc needs nothing more: focus-return.lua puts focus back on the pane it came from.
[ -n "$key" ] && rexboard jump "$key"
