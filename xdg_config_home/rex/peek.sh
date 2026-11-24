#!/bin/sh
# Peek: list agent panes (most urgent first) with a live preview of each pane's
# last lines, and answer it, without leaving the current tab.
#   1-9     answer: if the pane shows a dialog, pick option N; otherwise send
#           "N" as a line (for numbered next steps). An option that grants
#           something for later ("always allow") needs the same digit twice.
#           A digit answers only the dialog the preview shows; if the pane has
#           moved on since, nothing is sent and the header says to look again.
#           For a rexchat pane the dialog comes from rexchat's status file, and a
#           question's options are picked the same way, one per digit.
#   ctrl-t  type a line and send it to the pane (on a rexchat multi-select
#           question, "1,3" picks exactly those options)
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
# The look is rexchat's (rexchat_lib/theme.py): Catppuccin Frappé, coloured text on
# dark tints, filled colour only for title tabs, chips and option 1's number.
# Colours are "r;g;b" for truecolour SGR. Glyphs are Nerd Font ones, or with
# REXCHAT_PLAIN=1 the plain fallbacks rexchat uses.
esc=$(printf '\033')
glyphs() { slant=$1 g_ask=$2 g_question=$3 g_plan=$4 g_reply=$5 g_app=$6; }
if [ "${REXCHAT_PLAIN:-0}" = 0 ]; then
  # U+E0BC slant, U+F059 ask, U+F128 question, U+F0AE plan, U+F112 reply, U+F120 app.
  # shellcheck disable=SC2046  # split on purpose: one printf for all glyphs
  glyphs $(printf '\356\202\274 \357\201\231 \357\204\250 \357\202\256 \357\204\222 \357\204\240')
else
  glyphs '▌' '?' '?' '☰' '↩' '▶'
fi
c_text='198;208;245' c_ov='115;121;148' c_s0='65;69;89'
c_base='48;52;70' c_crust='35;38;52' c_lav='186;187;241' c_yellow='229;200;144'
c_yellow_tint='93;89;88'
# A title tab: dark bold LABEL on COLOUR, slanted right edge.
tab() { printf '%s' "${esc}[0;1;38;2;$c_crust;48;2;${2}m$1${esc}[0;38;2;$2;48;2;${c_base}m$slant${esc}[0m"; }
# Key hints like rexchat's footer: the key on a chip, what it does dim beside it.
hint() { printf '%s' "${esc}[0;38;2;$c_text;48;2;${c_s0}m $1 ${esc}[0;38;2;${c_ov}m $2 ${esc}[0m"; }
# A rexchat pane's dialog is not on rexboard's card: read it from rexchat's status
# file. Card JSON on stdin, KEY as $1; out comes the card with .dialog set to
# "ID:INDEX" (dialog.id, and dialog.index for a question, else 0), .options from
# the dialog, the question in .msg, .asking (what --asking must match) and .chat
# (the dialog). Other cards, and a pane with no readable status file, pass as they are.
chat_card() {
  st=${REXCHAT_STATE_DIR:-$HOME/.local/state/rexchat}/$(printf '%s' "${1##*/}" | sed 's/^block://').json
  [ -r "$st" ] || { cat; return; }
  jq -c --slurpfile st "$st" '
    ($st[0].dialog) as $d |
    if .harness != "rexchat" then .
    elif $d == null then .dialog = null | .options = []
    else .dialog = "\($d.id):\($d.index // 0)" | .chat = $d | .asking = ($st[0].asking // "") |
      (if $d.kind == "question" then
        .msg = "\(if ($d.header // "") == "" then "Question" else $d.header end) (\($d.index + 1) of \($d.count)): \($d.question)" +
        (if $d.multi then " [several: ctrl-t, then e.g. 1,3]" else "" end) else . end) |
      .options = [$d.options | to_entries[] | (.key + 1) as $n |
        {digit: $n, label: .value, lasting: any($d.lasting[]; . == $n)}]
    end'
}
# jq: text without terminal escape sequences (CSI, OSC, other ESC codes) and C0/C1
# control characters other than tab and newline. Applied to pane- and agent-supplied
# text before it is printed (presentation only; keys and dialog ids are left alone).
jq_clean='def clean: if type != "string" then . else gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "") |
  gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)?"; "") | gsub("\u001b[@-Z\\\\-_]?"; "") |
  gsub("[\\x{0}-\\x{8}\\x{b}-\\x{1f}\\x{7f}-\\x{9f}]"; "") end;'
if [ "$1" = --rows ]; then
  # key; the row as shown: a dot and status in the state's colour (needs you
  # yellow, running peach, the rest neutral), where, harness, message; and the
  # preview label for this row (a title tab, written for printf %b).
  rexboard ls --json | jq -r --arg slant "$slant" "$jq_clean"'
    def fg(c): "\u001b[38;2;" + c + "m";
    def rs: "\u001b[0m";
    def flat: gsub("[\t\r\n]+"; " ") | clean;
    def cut(n): if length > n then .[0:n-1] + "…" else . end;
    def fit(n): cut(n) | . + (" " * (n - length + 1))[1:];
    .[] |
    (if .group == "needs_you" then "229;200;144" elif .group == "working" then "239;159;118"
     elif .group == "quiet" then "165;173;206" else "115;121;148" end) as $c |
    (if .group == "needs_you" then "needs you" elif .group == "working" then "running" else .state | clean end) as $s |
    (.harness | sub("-code$"; "") | clean) as $h |
    (if $h == "claude" then "239;159;118" elif $h == "codex" then "129;200;190"
     elif $h == "rexchat" then "202;158;230" else "165;173;206" end) as $hc |
    ((.session + " › " + .tab) | flat) as $name |
    [ .key,
      fg($c) + (if .group == "needs_you" or .group == "working" then "●" else "○" end) + " " +
        "\u001b[1m" + fg("198;208;245") + ($name | fit(48)) + rs + "  " + fg($c) + ($s | fit(10)) +
        fg($hc) + ($h | fit(8)) + fg("115;121;148") + ((.msg // .title // "") | flat) + rs,
      ("\u001b[0;1;38;2;35;38;52;48;2;" + $c + "m " + ($name | cut(60)) + " \u001b[0;38;2;" + $c +
        ";48;2;48;52;70m" + $slant + rs | gsub("\\\\"; "\\\\") | gsub("\u001b"; "\\0033"))
    ] | join("\t")'
  exit
fi
# The other modes run inside fzf and keep their state in the peek's $PEEK_DIR.
[ $# -eq 0 ] || [ -d "$PEEK_DIR" ] || exit 1
if [ "$1" = --preview ]; then
  # The pane as it looks, colours included, under a three-line heading (pinned
  # by the preview window): where and state, the message, and the options the
  # digits pick on one line (or a hint when digits send a line); below the
  # capture, a card with what each digit picks. The heading, the card, the
  # digits and the dialog ID the answer keys send to all
  # come from one `rexboard show` read, taken before the capture; the ID is
  # recorded in $PEEK_DIR/shown once the preview is drawn, so a digit answers
  # only the dialog shown here.
  key=$2
  rm -f "$PEEK_DIR/shown"
  card=$(rexboard show --json "$key") || { echo "no such pane"; exit; }
  card=$(printf '%s' "$card" | chat_card "$key")
  # One jq run draws the heading (state, harness and dialog kind as chips, then
  # where; the message; the options in one line, so they stay in view however
  # the preview is scrolled) and, after a record separator, the dialog card
  # drawn like rexchat's. The card goes under the capture: the preview follows
  # the end, so it stays in view. Every string of the card is cleaned first.
  rsep=$(printf '\036')
  view=$(printf '%s' "$card" | jq -r --argjson w "${FZF_PREVIEW_COLUMNS:-80}" --arg slant "$slant" \
    --arg ask "$g_ask" --arg question "$g_question" --arg plan "$g_plan" --arg reply "$g_reply" "$jq_clean"'
    walk(clean) |
    def oneline: gsub("[\r\n\t]+"; " ");
    def cut(n): if length > n then .[0:n-1] + "…" else . end;
    def fg(c): "\u001b[38;2;" + c + "m";
    def bg(c): "\u001b[48;2;" + c + "m";
    def rs: "\u001b[0m";
    def rep(s; n): if n > 0 then s * n else "" end;
    def seg(t; st): {t: t, st: st};
    # A card line from segments: cut to the inner width IN, padded, between edges in colour E.
    def line($in; $e):
      reduce .[] as $s ({n: 0, a: ""};
        ($in - .n) as $room |
        if $room <= 0 then .
        elif ($s.t | length) <= $room then .n += ($s.t | length) | .a += $s.st + $s.t + rs
        else .n = $in | .a += $s.st + $s.t[0:$room - 1] + "…" + rs end) |
      fg($e) + "│" + rs + " " + .a + rep(" "; $in - .n) + " " + fg($e) + "│" + rs;
    # Segments cut to the width IN, with no edges (the pinned line of options).
    def pin($in):
      reduce .[] as $s ({n: 0, a: ""};
        ($in - .n) as $room |
        if $room <= 0 then .
        elif ($s.t | length) <= $room then .n += ($s.t | length) | .a += $s.st + $s.t + rs
        else .n = $in | .a += $s.st + $s.t[0:$room - 1] + "…" + rs end) | .a;
    # Card kinds: label, colour, its dark tint, a fainter band, edge colour, icon.
    {permission: ["Permission", "229;200;144", "93;89;88", "73;73;80", "211;185;137", $ask],
     question: ["Question", "140;170;238", "71;82;112", "61;69;94", "131;158;221", $question],
     plan: ["Plan ready", "202;158;230", "86;78;110", "70;67;92", "187;147;214", $plan],
     reply: ["Reply", "129;200;190", "68;89;100", "59;73;87", "121;185;178", $reply],
     dialog: ["Dialog", "229;200;144", "93;89;88", "73;73;80", "211;185;137", $ask]} as $kinds |
    (.chat.kind // (if (.dialog // "") == "" then "reply" else (.kind // "dialog") end)) as $k |
    (if $kinds[$k] then $k else "dialog" end) as $kind |
    $kinds[$kind] as [$kname, $kc, $kt, $kb, $ke, $ki] |
    (if .group == "needs_you" then ["229;200;144", "93;89;88", "needs you"]
     elif .group == "working" then ["239;159;118", "96;79;82", "running"]
     elif .group == "quiet" then ["165;173;206", "77;82;104", .state]
     else ["115;121;148", "65;69;90", .state] end) as [$sc, $st, $sw] |
    (.harness | sub("-code$"; "")) as $h |
    (if $h == "claude" then "239;159;118" elif $h == "codex" then "129;200;190"
     elif $h == "rexchat" then "202;158;230" else "165;173;206" end) as $hc |
    ((.options | length) > 0) as $any |
    bg($st) + fg($sc) + " ● " + $sw + " " + rs + " " + bg("65;69;89") + fg($hc) + " " + $h + " " + rs +
    (if $any then " " + bg($kt) + fg($kc) + " " + ($kname | ascii_downcase) + " " + rs else "" end) +
    "  " + fg("165;173;206") + (.where // "") + rs + "\n" +
    "\u001b[1m" + fg("198;208;245") + ((.msg // .title // "") | oneline) + rs + "\n" +
    (if $any then
       # What each digit picks, in one line: every label cut to an equal share of the width.
       (.options | length) as $n |
       ((($w - 7 * $n + 3) / $n) | floor | if . < 4 then 4 else . end) as $each |
       [.options | to_entries[] | (if .key > 0 then [seg(" · "; fg("115;121;148"))] else [] end) +
         [seg(" \(.value.digit) "; fg($kc) + bg($kt)), seg(" " + (.value.label | oneline | cut($each)); fg("165;173;206"))]
       ] | add | pin($w)
     else fg("115;121;148") + "1-9 send the digit as a line · ctrl-t types a line " +
       fg("81;87;109") + rep("─"; $w - 51) end) + rs + "\u001e" +
    if ($any | not) then "" else
      ($w - 4) as $in |
      (" " + $ki + " " + $kname + " ") as $label |
      (if $kind == "question" and .chat.count then
         "\(.chat.index + 1) of \(.chat.count)" + (if (.chat.header // "") != "" then " · " + .chat.header else "" end)
       elif $kind == "reply" then "options from the reply"
       elif (.chat.waiting // 1) > 1 then "+\(.chat.waiting - 1) waiting"
       else "" end | oneline | cut($w / 3 | floor)) as $meta |
      (if $kind == "permission" and (.chat.title // "") != "" then
         [[seg(" $ " + (.chat.title | oneline) + " "; fg("239;159;118") + bg("41;44;60"))]]
       elif $kind == "plan" then
         ((.chat.plan // "") | split("\n") | map(select(test("\\S")))) as $p |
         if ($p | length) > 0 then $p[0:6] | map([seg(oneline; fg("165;173;206"))])
         else [[seg(.chat.title // "" | oneline; fg("165;173;206"))]] end
       elif $kind == "question" and (.chat.question // "") != "" then
         [[seg(.chat.question | oneline; "\u001b[1m" + fg("198;208;245"))]] +
         (if .chat.multi then [[seg("several: ctrl-t, then e.g. 1,3"; fg("115;121;148"))]] else [] end)
       else [] end) as $body |
      (.options | map(
        (.label | oneline) as $l |
        if .digit == 1 then
          [seg(" 1 "; "\u001b[1m" + fg("35;38;52") + bg($kc)), seg(" " + $l + " "; "\u001b[1m" + fg("198;208;245") + bg($kb))]
        else [seg(" \(.digit) "; fg($kc) + bg($kt)), seg(" " + $l; fg("165;173;206"))] end +
        (if .lasting then [seg(" · press twice"; fg("115;121;148"))] else [] end))) as $opts |
      (["digits pick"] +
       (if any(.options[]; .lasting) then ["lasting: press twice"] else [] end) +
       (if $kind == "question" and .chat.multi then ["ctrl-t: 1,3 picks several"]
        elif .harness == "rexchat" and $kind != "reply" then []
        else ["ctrl-t types a reply"] end) +
       ["enter goes there"] | join(" · ") | cut($w - 6)) as $hint |
      "\n" + fg($ke) + "╭─" + rs + "\u001b[1m" + fg("35;38;52") + bg($kc) + $label + rs + fg($kc) + $slant + rs +
      fg($ke) + rep("─"; $w - 5 - ($label | length) - (if $meta == "" then 0 else ($meta | length) + 2 end)) + rs +
      (if $meta == "" then "" else " " + fg("115;121;148") + $meta + rs + " " end) + fg($ke) + "─╮" + rs + "\n" +
      ((if ($body | length) > 0 then $body + [[]] else [] end) + $opts | map(line($in; $ke)) | join("\n")) + "\n" +
      fg($ke) + "╰" + rep("─"; $w - 5 - ($hint | length)) + rs + " " + fg("115;121;148") + $hint + rs + " " +
      fg($ke) + "─╯" + rs
    end')
  printf '%s\n' "${view%%"$rsep"*}"
  # The capture skips blank cells with cursor-forward codes, which fzf does not
  # draw; turn them into spaces.
  rex capture -s "$(printf '%s' "$card" | jq -r .session_id)" -b "${key#*/}" --trim --format=vt |
    tail -n 80 | perl -pe 's/\e\[(\d*)C/" " x ($1 || 1)/ge; s/\r//g'
  [ -z "${view#*"$rsep"}" ] || printf '%s\n' "${view#*"$rsep"}"
  # "-" stands for "no dialog": read with IFS=tab would merge an empty field
  # with its neighbour, since tab is IFS whitespace.
  printf '%s' "$card" | jq -r --arg k "$key" \
    '[$k, (.dialog // "" | if . == "" then "-" else . end), (.options | length)] | @tsv' \
    >"$PEEK_DIR/shown.$$" && mv -f "$PEEK_DIR/shown.$$" "$PEEK_DIR/shown"
  exit
fi
if [ "$1" = --header ]; then
  # The header: the last answer's result or rexboard's refusal, as a yellow chip
  # (nothing when there is none). The key hints sit on the list's bottom edge.
  # The message names the pane ($where, from the board), so it is cleaned too.
  msg=$(jq -Rrs "$jq_clean"' clean' "$PEEK_DIR/msg" 2>/dev/null)
  [ -z "$msg" ] || printf '%s' "${esc}[0;38;2;$c_yellow;48;2;${c_yellow_tint}m $g_ask $msg ${esc}[0m"
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
  card=$(printf '%s' "$card" | chat_card "$key")
  where=$(printf '%s' "$card" | jq -r '.where')
  if [ "$(printf '%s' "$card" | jq -r '.dialog // ""')" != "$dialog" ]; then
    rm -f "$PEEK_DIR/confirm"
    echo "the dialog changed; look again" >"$PEEK_DIR/msg"; exit 0
  fi
  if [ "$mode" = --reply ] && [ "$(printf '%s' "$card" | jq -r '.harness // ""')" = rexchat ] &&
    [ -n "$dialog" ] && [ "$(printf '%s' "$card" | jq -r '.chat.multi // false')" != true ] &&
    [ "$(printf '%s' "$card" | jq -r '.chat.kind // ""')" != reply ]; then
    # rexchat takes no typed line while a dialog is up (its Reply card is not one).
    if [ "$(printf '%s' "$card" | jq -r '.chat.kind // ""')" = question ]; then
      echo "this question takes a digit; to type your own answer, pick Other in the pane" >"$PEEK_DIR/msg"
    else
      echo "a dialog is up in $where: pick a digit first" >"$PEEK_DIR/msg"
    fi
    exit 0
  fi
  if [ "$mode" = --reply ]; then
    printf '\n  reply to %s (empty cancels): ' "$where" >/dev/tty
    IFS= read -r text </dev/tty
    [ -n "$text" ] || exit 0
    if [ "$(printf '%s' "$card" | jq -r '.chat.multi // false')" = true ] &&
      printf '%s' "$text" | grep -Eq '^[1-9](,[1-9])*$'; then
      # A rexchat multi-select question: "1,3" picks exactly those options.
      set -- --pick "$text"
      sent="picked options $text in $where"
    else
      set -- --text "$text"
      sent="reply sent to $where"
    fi
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
  if [ "$(printf '%s' "$card" | jq -r '.harness // ""')" = rexchat ]; then
    # rexboard types only into harnesses it knows. rexchat takes the answer over
    # its own socket instead, and checks the request is still the one shown: the
    # dialog id and question index (for a question) the preview showed, and the
    # title. A lasting option goes with --confirm only on the second press (above).
    case $1 in
      --pick) shift
        # --opt=VALUE forms: a value that starts with "-" is not taken for an option.
        set -- "--answer=$1" "--dialog=${dialog%%:*}" "--asking=$(printf '%s' "$card" | jq -r '.asking // ""')" \
          ${2:+"$2"}
        [ "$(printf '%s' "$card" | jq -r '.chat.kind // ""')" = question ] && set -- "$@" "--question=${dialog#*:}" ;;
      --text) set -- "--say=$2" ;;
    esac
    answer() { rexchat --block "$key" "$@"; }
  else
    answer() { rexboard answer "$key" --dialog "$dialog" "$@"; }
  fi
  if out=$(answer "$@" 2>&1); then
    echo "$sent" >"$PEEK_DIR/msg"
    # Wait (at most 3s) for the board to see the answer, so the reload drops the row.
    i=0
    while [ $i -lt 15 ] &&
      [ "$(rexboard show --json "$key" | chat_card "$key" | jq -r '.dialog // ""')" = "$dialog" ]; do
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

# The look: the prompt is a title tab; the list sits in a rounded frame with the
# key hints on its bottom edge and the header (the last result) inside its top;
# the preview has its own frame, labelled with the focused row's tab (field 3).
# The current row is a dark tint, never a bright fill.
hints=" $(hint 1-9 answer)$(hint ctrl-t reply)$(hint enter go)$(hint ctrl-s seen)$(hint esc close)"
key=$("$self" --rows | fzf \
  --ansi --delimiter='\t' --with-nth=2 --no-sort --layout=reverse \
  --color='dark,fg:#c6d0f5,bg:#303446,preview-fg:#c6d0f5,preview-bg:#303446' \
  --color='fg+:#c6d0f5:regular:bold,bg+:#43475e,gutter:#303446,hl:#e5c890:regular:bold,hl+:#e5c890:regular:bold' \
  --color='query:#c6d0f5:regular,ghost:#737994,prompt:#ca9ee6,info:#737994,spinner:#ef9f76' \
  --color='pointer:#babbf1,marker:#a6d189,header:#a5adce:regular,label:#c6d0f5' \
  --color='border:#51576d,list-border:#626880,preview-border:#626880,input-border:#ca9ee6,header-border:#51576d' \
  --color='scrollbar:#51576d,preview-scrollbar:#51576d,separator:#414559' \
  --prompt="$(tab " $g_app Peek " "$c_lav") " --pointer='▌' --info=inline-right --no-separator \
  --ghost='letters filter · digits answer' --highlight-line \
  --list-border=rounded --list-label="$hints " --list-label-pos=-2:bottom \
  --preview-label-pos=2 --bind='focus:transform-preview-label(printf %b {3})' \
  --bind='result:transform-preview-label(printf %b {3})' \
  --preview="$self --preview {1}" \
  --preview-window='down,75%,follow,border-rounded,~3' \
  --bind="ctrl-s:execute-silent(rexboard seen {1})+change-header()+reload($self --rows)" \
  --bind="ctrl-t:execute($self --reply {1})$after" \
  --bind='load:first' \
  "$@" |
  cut -f1)

# Esc needs nothing more: focus-return.lua puts focus back on the pane it came from.
[ -n "$key" ] && rexboard jump "$key"
