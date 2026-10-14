# shellcheck shell=bash
# tui.sh — native dialogs for proxdump, drawn in bash instead of whiptail.
#
# Sourced by proxdump when the native interface is selected: it replaces the
# dialog helpers (msg, confirm, input, menu, checklist, textbox, busy, the
# progress gauge and the summary) by functions with the same arguments and
# the same results, so the rest of the tool does not change.
#
# Look: header bar, one window with rounded borders in the middle of the
# screen, footer with the keys; colours on the background of the terminal.
# Every frame is composed in one string and written at once.

# --- Themes ------------------------------------------------------------------
# A theme gives each element its SGR parameters (TH[element]); the files of
# $THEME_DIR only list what differs from the default theme below.

# shellcheck disable=SC2034  # read by the Configuration menu of proxdump
THEME_DIR="$(dirname "$LIB_DIR")/themes"
# shellcheck disable=SC2034
THEME_IDS=(default dracula nord gruvbox catppuccin tokyonight solarized light basic)
# shellcheck disable=SC2034
declare -A THEME_NAMES=([default]="Default" [dracula]="Dracula" [nord]="Nord"
    [gruvbox]="Gruvbox" [catppuccin]="Catppuccin" [tokyonight]="Tokyo Night"
    [solarized]="Solarized" [light]="Light (for terminals with a light background)"
    [basic]="Basic (8 colours)")
# i18n: "Default" "Light (for terminals with a light background)" "Basic (8 colours)"
declare -A TH=() K=() G=()
THEME=default

theme_load() {
    local name=${PROXDUMP_THEME:-${UI_THEME:-}} k
    if [[ -z $name || $name == auto ]]; then
        if (($(tput colors 2>/dev/null || echo 8) >= 256)); then name=default; else name=basic; fi
    fi
    [[ $name == default || -r $THEME_DIR/$name.sh ]] || name=default
    TH=(
        [norm]="39"                    # text
        [dim]="38;5;245"               # secondary text
        [border]="38;5;240"            # frame of the window
        [title]="1;38;5;208"           # title in the frame
        [bold]="1"                     # outcome of an operation, heading
        [header]="38;5;252;48;5;236"   # top bar
        [header_dim]="38;5;245;48;5;236"
        [logo]="1;38;5;208;48;5;236"
        [sel]="38;5;255;48;5;25"       # selected line, focused button
        [btn]="38;5;252;48;5;238"      # other buttons
        [field]="38;5;255;48;5;236"    # input field
        [ok]="38;5;71"
        [err]="38;5;203"
        [accent]="38;5;208"            # tags of the menus, spinner
        [bar_fill]="38;5;33"
        [bar_empty]="38;5;238"
        [footer]="38;5;250;48;5;236"   # bottom bar
        [footer_key]="1;38;5;208;48;5;236"
    )
    # shellcheck disable=SC1090
    [[ $name != default ]] && source "$THEME_DIR/$name.sh"
    # shellcheck disable=SC2034
    THEME=$name
    K=([norm]=$'\e[0m')
    for k in "${!TH[@]}"; do K[$k]=$'\e[0;'"${TH[$k]}m"; done
}

# Drawing characters: Unicode, or 7-bit ASCII where the terminal cannot show
# them (Linux console, terminal that is not UTF-8)
glyphs_load() {
    local set=${PROXDUMP_GLYPHS:-}
    if [[ -z $set ]]; then
        set=unicode
        [[ ${TERM:-} == linux || ${UTF8_FORCED:-0} == 1 ]] && set=ascii
    fi
    if [[ $set == ascii ]]; then
        G=([h]="-" [v]="|" [tl]="+" [tr]="+" [bl]="+" [br]="+" [check]="x" [bar]="#" [cut]="~" [ud]="Up/Down" [lr]="Left/Right")
        SPIN=('|' '/' '-' '\')
    else
        G=([h]="─" [v]="│" [tl]="╭" [tr]="╮" [bl]="╰" [br]="╯" [check]="✔" [bar]="━" [cut]="…" [ud]="↑↓" [lr]="←→")
        SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    fi
}

TUI_ON=0
TUI_STTY=""
TUI_TITLE="" # title of the next window
TUI_RESIZED=0
FRAME=""

# --- Terminal ----------------------------------------------------------------

tui_enter() {
    ((TUI_ON)) && return 0
    theme_load
    glyphs_load
    TUI_STTY=$(stty -g </dev/tty 2>/dev/null)
    printf '\e[?1049h\e[?25l' >/dev/tty
    TUI_ON=1
}

tui_leave() {
    ((TUI_ON)) || return 0
    TUI_ON=0
    printf '\e[?1000l\e[?1006l\e[0m\e[?25h\e[?1049l' >/dev/tty
    [[ -n $TUI_STTY ]] && stty "$TUI_STTY" </dev/tty 2>/dev/null
}

_size() {
    local s
    s=$(stty size </dev/tty 2>/dev/null) || s="24 80"
    read -r ROWS COLS <<<"$s"
    ((ROWS < 8)) && ROWS=8
    ((COLS < 30)) && COLS=30
    WW=$((COLS - 6)); ((WW > 100)) && WW=100; ((WW < 26)) && WW=$((COLS - 2))
    WL=$(((COLS - WW) / 2 + 1))
    IW=$((WW - 4)) # width of the contents of the window
}

# Keys are read one at a time, without echo, and those typed before the
# dialog opened are discarded. The echo stays off after it closes (dialogs
# run in sub-shells: nothing else survives); screen turns it on again.
_begin() {
    kbd_hush
    kbd_drain
    TUI_RESIZED=0
    trap 'TUI_RESIZED=1' WINCH
    [[ ${UI_MOUSE:-1} == 1 ]] && printf '\e[?1000h\e[?1006h' >/dev/tty
    return 0
}
_end() {
    printf '\e[?1000l\e[?1006l' >/dev/tty
    kbd_hush
}

# -> KEY: a name (UP, ENTER, ESC, CLICK, RESIZE…) or the character typed.
# CLICK and the wheel set MX and MY, the cell under the pointer.
_key() {
    local k rest="" c rc
    KEY=""
    while :; do
        if ((TUI_RESIZED)); then
            TUI_RESIZED=0
            KEY=RESIZE
            return 0
        fi
        IFS= read -rsn1 -t 0.3 k </dev/tty
        rc=$?
        ((rc == 0)) && break
        ((rc > 128)) && continue # nothing typed yet
        KEY=ESC                  # the terminal is gone
        return 1
    done
    case $k in
    $'\e')
        IFS= read -rsn2 -t 0.05 rest </dev/tty
        if [[ $rest == '[<' ]]; then
            # mouse report: ESC [ < button ; column ; row (M = press)
            while IFS= read -rsn1 -t 0.05 c </dev/tty; do
                rest+=$c
                [[ $c == [Mm] ]] && break
            done
            KEY=UNKNOWN
            if [[ $rest =~ ^\[\<([0-9]+)\;([0-9]+)\;([0-9]+)M$ ]]; then
                MX=${BASH_REMATCH[2]} MY=${BASH_REMATCH[3]}
                case ${BASH_REMATCH[1]} in
                0) KEY=CLICK ;;
                64) KEY=WHEELUP ;;
                65) KEY=WHEELDOWN ;;
                esac
            fi
            return 0
        fi
        if [[ $rest == \[[0-9] ]]; then
            while IFS= read -rsn1 -t 0.05 c </dev/tty; do
                rest+=$c
                [[ $c == [~A-Za-z] ]] && break
            done
        fi
        case $rest in
        '[A' | OA) KEY=UP ;;
        '[B' | OB) KEY=DOWN ;;
        '[C' | OC) KEY=RIGHT ;;
        '[D' | OD) KEY=LEFT ;;
        '[H' | OH | '[1~') KEY=HOME ;;
        '[F' | OF | '[4~') KEY=END ;;
        '[5~') KEY=PGUP ;;
        '[6~') KEY=PGDN ;;
        '[3~') KEY=DEL ;;
        '[Z') KEY=BTAB ;;
        '') KEY=ESC ;;
        *) KEY=UNKNOWN ;;
        esac
        ;;
    '') KEY=ENTER ;;
    $'\t') KEY=TAB ;;
    $'\x7f' | $'\b') KEY=BACKSPACE ;;
    *) KEY=$k ;;
    esac
}

# --- Text --------------------------------------------------------------------

# Display width (REPLY): Chinese and full-width characters take two columns
_dw() {
    local LC_COLLATE=C wide
    wide=${1//[$'\u0001'-$'⹿']/}
    REPLY=$((${#1} + ${#wide}))
}

# REPLY = the string on exactly that many columns (cut or padded)
_pad() {
    local s=$1 w=$2 out="" i c cw=0
    ((w < 1)) && { REPLY=""; return; }
    _dw "$s"
    if ((REPLY > w)); then
        for ((i = 0; i < ${#s}; i++)); do
            c=${s:i:1}
            _dw "$c"
            ((cw + REPLY > w - 1)) && break
            out+=$c
            cw=$((cw + REPLY))
        done
        s="$out${G[cut]}"
        _dw "$s"
    fi
    printf -v REPLY '%s%*s' "$s" $((w - REPLY)) ''
}

# Wraps a text (with real or literal "\n" line breaks) -> WR[]
_wrap() {
    local text=${1//\\n/$'\n'} w=$2 line word cur cw ww i c
    local -a words
    WR=()
    ((w < 4)) && w=4
    while IFS= read -r line; do
        _dw "$line"
        if ((REPLY <= w)); then
            WR+=("$line")
            continue
        fi
        cur="" cw=0
        read -ra words <<<"$line"
        for word in "${words[@]}"; do
            _dw "$word"
            ww=$REPLY
            if ((cw > 0 && cw + 1 + ww <= w)); then
                cur+=" $word"
                cw=$((cw + 1 + ww))
                continue
            fi
            ((cw > 0)) && WR+=("$cur")
            cur="" cw=0
            if ((ww <= w)); then
                cur=$word cw=$ww
                continue
            fi
            # a word wider than the window (path, text without spaces)
            for ((i = 0; i < ${#word}; i++)); do
                c=${word:i:1}
                _dw "$c"
                if ((cw + REPLY > w)); then
                    WR+=("$cur")
                    cur="" cw=0
                fi
                cur+=$c
                cw=$((cw + REPLY))
            done
        done
        ((cw > 0)) && WR+=("$cur")
    done <<<"$text"
}

# --- Drawing -----------------------------------------------------------------

_at() { FRAME+=$'\e['"$1;$2"'H'"$3"; }

# Starts a frame: header bar, cleared screen, footer with the key hints
# ("key:label" pairs)
_chrome() {
    local hint left right pad note
    FRAME=$'\e[?25l\e[H\e[J'
    # whether this is the latest version, if it fits
    note=${VERSION_NOTE:+"· $VERSION_NOTE "}
    right=" $(hostname -s) "
    _dw " PROXDUMP ${VERSION} $note$right"
    if ((REPLY > COLS)); then
        note=""
        _dw " PROXDUMP ${VERSION} $right"
    fi
    pad=$((COLS - REPLY)); ((pad < 0)) && pad=0
    printf -v pad '%*s' "$pad" ''
    _at 1 1 "${K[logo]} PROXDUMP ${K[header_dim]}${VERSION} ${note}${K[header]}${pad}${K[header_dim]}${right}${K[norm]}"
    left=""
    for hint; do
        left+="${hint%%:*} ${hint#*:}  "
    done
    _pad " $left" "$COLS"
    left=$REPLY
    # the keys stand out: each hint starts with its key
    for hint; do
        left=${left/"${hint%%:*} ${hint#*:}"/"${K[footer_key]}${hint%%:*}${K[footer]} ${hint#*:}"}
    done
    _at "$ROWS" 1 "${K[footer]}${left}${K[norm]}"
}

# Draws the frame of a window of h rows, centred; sets WT (its first row)
_window() {
    local h=$1 title=${TUI_TITLE:-} r line
    ((h > ROWS - 2)) && h=$((ROWS - 2))
    WT=$(((ROWS - h) / 2 + 1)); ((WT < 2)) && WT=2
    printf -v line '%*s' $((WW - 2)) ''
    line=${line// /${G[h]}}
    if [[ -n $title ]]; then
        _pad " $title " $((WW - 4))
        title=${REPLY%"${REPLY##*[! ]}"}
        _dw "$title "
        _at "$WT" "$WL" "${K[border]}${G[tl]}${G[h]}${K[title]}${title} ${K[border]}${line:0:WW-3-REPLY}${G[tr]}"
    else
        _at "$WT" "$WL" "${K[border]}${G[tl]}${line}${G[tr]}"
    fi
    for ((r = 1; r < h - 1; r++)); do
        _at $((WT + r)) "$WL" "${K[border]}${G[v]}$(printf '%*s' $((WW - 2)) '')${G[v]}"
    done
    _at $((WT + h - 1)) "$WL" "${K[border]}${G[bl]}${line}${G[br]}${K[norm]}"
}

# One line of contents: row inside the window (1 = first), text, colour
_line() {
    _pad "$2" "$IW"
    _at $((WT + $1)) $((WL + 2)) "${3:-${K[norm]}}${REPLY}${K[norm]}"
}

_flush() { printf '%s' "$FRAME" >/dev/tty; }

_text_colour() { # a line of a message -> its colour
    case $1 in
    ERROR* | "rclone: "*) REPLY=${K[err]} ;;
    *) REPLY=${K[norm]} ;;
    esac
}

# Buttons centred on a row: index of the focused one, then the labels.
# Their cells are recorded for the mouse (BTN_ROW, BTN_X1, BTN_X2).
_buttons() {
    local row=$1 focus=$2 i=0 w=0 b line="" x
    shift 2
    for b; do
        _dw "$b"
        w=$((w + REPLY + 4))
    done
    x=$((WL + (WW - w) / 2 + 1))
    BTN_ROW=$((WT + row)) BTN_X1=() BTN_X2=()
    _at "$BTN_ROW" "$x" ""
    for b; do
        if ((i == focus)); then line+="${K[sel]} $b ${K[norm]}  "; else line+="${K[btn]} $b ${K[norm]}  "; fi
        _dw "$b"
        BTN_X1+=("$x")
        BTN_X2+=("$((x + REPLY + 1))")
        x=$((x + REPLY + 4))
        i=$((i + 1))
    done
    FRAME+=$line
}

# --- Dialogs -----------------------------------------------------------------

# A text and buttons. REPLY = index of the button chosen; fails on Esc.
_dialog() { # text, focused button, labels…
    local text=$1 focus=$2 n body scroll=0 r h rc=0 i
    shift 2
    local -a labels=("$@") hints
    _begin
    while :; do
        _size
        _wrap "$text" "$IW"
        n=${#WR[@]}
        body=$n
        ((body > ROWS - 8)) && body=$((ROWS - 8))
        ((body < 1)) && body=1
        ((scroll > n - body)) && scroll=$((n - body))
        ((scroll < 0)) && scroll=0
        hints=("Enter:$(t "Confirm")")
        ((${#labels[@]} > 1)) && hints=("${G[lr]}:$(t "Choose")" "${hints[@]}" "Esc:$(t "Cancel")")
        ((n > body)) && hints+=("${G[ud]}:$(t "Scroll") $((scroll + 1))-$((scroll + body))/$n")
        _chrome "${hints[@]}"
        h=$((body + 5))
        _window "$h"
        for ((r = 0; r < body; r++)); do
            _text_colour "${WR[scroll + r]:-}"
            _line $((r + 2)) "${WR[scroll + r]:-}" "$REPLY"
        done
        # the first line of a summary is its outcome
        [[ -n $TUI_TITLE && $scroll == 0 ]] && _line 2 "${WR[0]:-}" "${K[bold]}"
        _buttons $((body + 3)) "$focus" "${labels[@]}"
        _flush
        _key
        case $KEY in
        ENTER) break ;;
        ESC) rc=1; break ;;
        LEFT | BTAB) focus=$(((focus + ${#labels[@]} - 1) % ${#labels[@]})) ;;
        RIGHT | TAB) focus=$(((focus + 1) % ${#labels[@]})) ;;
        UP | WHEELUP) scroll=$((scroll - 1)) ;;
        DOWN | WHEELDOWN) scroll=$((scroll + 1)) ;;
        PGUP) scroll=$((scroll - body + 1)) ;;
        PGDN | " ") scroll=$((scroll + body - 1)) ;;
        HOME) scroll=0 ;;
        END) scroll=$n ;;
        CLICK)
            if ((MY == BTN_ROW)); then
                for i in "${!BTN_X1[@]}"; do
                    ((MX >= BTN_X1[i] && MX <= BTN_X2[i])) && { focus=$i; break 2; }
                done
            fi
            ;;
        esac
    done
    _end
    REPLY=$focus
    return "$rc"
}

msg() {
    _dialog "$1" 0 "$(t "Ok")"
    return 0
}
confirm() { _dialog "$1" 0 "$(t "Yes")" "$(t "No")" && ((REPLY == 0)); }
confirm_no() { _dialog "$1" 1 "$(t "Yes")" "$(t "No")" && ((REPLY == 0)); }

# Line editor under a text; prints the value. $3 = 1 hides the characters.
_edit() {
    local text=$1 val=${2:-} hide=${3:-0} pos n r shown before start rc=0
    pos=${#val}
    _begin
    while :; do
        _size
        _wrap "$text" "$IW"
        n=${#WR[@]}
        ((n > ROWS - 9)) && n=$((ROWS - 9))
        _chrome "Enter:$(t "Confirm")" "Esc:$(t "Cancel")"
        _window $((n + 6))
        for ((r = 0; r < n; r++)); do _line $((r + 2)) "${WR[r]}"; done
        shown=$val
        if ((hide)); then
            printf -v shown '%*s' "${#val}" ''
            shown=${shown// /•}
        fi
        # keep the cursor in view when the value is longer than the field
        start=0
        before=${shown:0:pos}
        _dw "$before"
        while ((REPLY > IW - 2)); do
            start=$((start + 1))
            before=${shown:start:pos-start}
            _dw "$before"
        done
        _line $((n + 3)) "${shown:start}" "${K[field]}"
        _dw "$before"
        FRAME+=$'\e['"$((WT + n + 3));$((WL + 2 + REPLY))"'H'$'\e[?25h'
        _flush
        _key
        case $KEY in
        ENTER) break ;;
        ESC) rc=1; break ;;
        LEFT) ((pos > 0)) && pos=$((pos - 1)) ;;
        RIGHT) ((pos < ${#val})) && pos=$((pos + 1)) ;;
        HOME) pos=0 ;;
        END) pos=${#val} ;;
        BACKSPACE) ((pos > 0)) && { val=${val:0:pos-1}${val:pos}; pos=$((pos - 1)); } ;;
        DEL) val=${val:0:pos}${val:pos+1} ;;
        $'\x15') val="" pos=0 ;; # Ctrl-U
        *)
            if [[ ${#KEY} == 1 && $KEY == [[:print:]] ]]; then
                val=${val:0:pos}$KEY${val:pos}
                pos=$((pos + 1))
            fi
            ;;
        esac
    done
    printf '\e[?25l' >/dev/tty
    _end
    ((rc == 0)) && printf '%s\n' "$val"
    return "$rc"
}
input() { _edit "$1" "${2:-}" 0; }
password() { _edit "$1" "" 1; }

# List with one line selected (mode menu) or several ticked (mode check)
_list() { # mode, text, entries: tag label [state]…
    local mode=$1 text=$2 step=2 i n lh top=0 sel=0 r tw=0 rc=0 nt title="" mark style line k cancel first
    shift 2
    [[ $mode == check ]] && step=3
    local -a tags=() labels=() on=() hints
    while (($# >= step)); do
        tags+=("$1")
        labels+=("$2")
        [[ $mode == check ]] && on+=("$([[ ${3,,} == on ]] && echo 1 || echo 0)")
        _dw "$1"
        ((REPLY > tw)) && tw=$REPLY
        shift "$step"
    done
    n=${#tags[@]}
    ((tw > 30)) && tw=30
    # a short heading goes into the border of the window
    if [[ $text != *\\n* && $text != *$'\n'* ]]; then
        _dw "$text"
        ((REPLY <= 70)) && { title=$text; text=""; }
    fi
    cancel=$(t "${CANCEL:-Cancel}")
    _begin
    while :; do
        _size
        WR=()
        [[ -n $text ]] && _wrap "$text" "$IW"
        nt=${#WR[@]}
        ((nt > ROWS - 9)) && nt=$((ROWS - 9))
        ((nt)) && nt=$((nt + 1))
        lh=$n
        ((lh > ROWS - 6 - nt)) && lh=$((ROWS - 6 - nt))
        ((lh < 1)) && lh=1
        ((sel < top)) && top=$sel
        ((sel >= top + lh)) && top=$((sel - lh + 1))
        hints=("${G[ud]}:$(t "Move")")
        [[ $mode == check ]] && hints+=("Space:$(t "Select")")
        hints+=("Enter:$(t "Confirm")" "Esc:$cancel")
        ((n > lh)) && hints+=("$((sel + 1))/$n:")
        _chrome "${hints[@]}"
        TUI_TITLE=$title
        _window $((lh + nt + 4))
        for ((r = 0; r < nt - 1; r++)); do _line $((r + 2)) "${WR[r]}"; done
        first=$((WT + nt + 2))
        for ((r = 0; r < lh; r++)); do
            i=$((top + r))
            mark=""
            if [[ $mode == check ]]; then
                if ((on[i])); then mark="[${G[check]}] "; else mark="[ ] "; fi
            fi
            _pad "${tags[i]}" "$tw"
            k=$REPLY
            if ((i == sel)); then
                _pad " $mark$k  ${labels[i]}" "$IW"
                line="${K[sel]}$REPLY"
            else
                _pad "${labels[i]}" $((IW - tw - 3 - ${#mark}))
                style=${K[accent]}
                [[ $mode == check ]] && ((on[i])) && mark="${K[ok]}[${G[check]}]${K[norm]} "
                line="${K[norm]} $mark$style$k${K[norm]}  $REPLY"
            fi
            _at $((first + r)) $((WL + 2)) "$line${K[norm]}"
        done
        _flush
        _key
        case $KEY in
        ENTER) break ;;
        ESC) rc=1; break ;;
        UP) sel=$(((sel + n - 1) % n)) ;;
        DOWN) sel=$(((sel + 1) % n)) ;;
        WHEELUP) ((sel > 0)) && sel=$((sel - 1)) ;;
        WHEELDOWN) ((sel < n - 1)) && sel=$((sel + 1)) ;;
        PGUP) sel=$((sel - lh)); ((sel < 0)) && sel=0 ;;
        PGDN) sel=$((sel + lh)); ((sel >= n)) && sel=$((n - 1)) ;;
        HOME) sel=0 ;;
        END) sel=$((n - 1)) ;;
        " ") [[ $mode == check ]] && on[sel]=$((1 - on[sel])) ;;
        CLICK)
            # a click opens the entry of a menu, ticks that of a checklist
            if ((MY >= first && MY < first + lh && MX > WL && MX < WL + WW - 1)); then
                sel=$((top + MY - first))
                [[ $mode == menu ]] && break
                on[sel]=$((1 - on[sel]))
            fi
            ;;
        *)
            # the first character of a tag moves to it
            if [[ ${#KEY} == 1 ]]; then
                for ((r = 1; r <= n; r++)); do
                    i=$(((sel + r) % n))
                    [[ ${tags[i],,} == "${KEY,,}"* ]] && { sel=$i; break; }
                done
            fi
            ;;
        esac
    done
    _end
    ((rc)) && return 1
    if [[ $mode == check ]]; then
        for i in "${!tags[@]}"; do ((on[i])) && printf '%s\n' "${tags[i]}"; done
    else
        printf '%s\n' "${tags[sel]}"
    fi
    return 0
}
menu() { _list menu "$@"; }
checklist() { _list check "$@"; }

textbox() { # title, file
    TUI_TITLE=$1
    _dialog "$(<"$2")" 0 "$(t "Ok")"
    TUI_TITLE=""
    return 0
}

# Notice displayed while the next dialog is being prepared
busy() {
    local r
    kbd_hush
    _size
    _chrome
    _wrap "$1" $((IW - 2))
    TUI_TITLE=""
    _window $((${#WR[@]} + 4))
    for r in "${!WR[@]}"; do _line $((r + 2)) "  ${WR[r]}"; done
    _at $((WT + 2)) $((WL + 2)) "${K[accent]}${SPIN[0]}${K[norm]}"
    _flush
}

# Steps that need the plain terminal (text to copy or to paste)
screen() { # heading
    [[ -n $TUI_STTY ]] && stty "$TUI_STTY" </dev/tty 2>/dev/null
    kbd_drain
    printf '\e[?1000l\e[?1006l\e[0m\e[?25h\e[H\e[J%s PROXDUMP %s %s %s\n\n' "${K[logo]}" "${K[header]}" "$1" "${K[norm]}"
}

# --- Progress ----------------------------------------------------------------

# Reads the gauge protocol on its input (XXX, percentage, four lines of
# text, XXX) and keeps the window up to date; the spinner turns meanwhile,
# and the window follows the size of the terminal.
_gauge_loop() {
    local heading=$1 line part="" pct=0 state=0 spin=0 fill bw bar start=$SECONDS rc resized=1
    local -a txt=("$heading" "" "" "") buf=()
    trap 'resized=1' WINCH
    while :; do
        IFS= read -r -t 0.12 line
        rc=$?
        # a timeout may fall in the middle of a line: what was read is kept
        # and completed by the next read
        if ((rc > 128)); then
            part+=$line
        elif ((rc == 0)); then
            line=$part$line
            part=""
        fi
        if ((rc == 0)); then
            if [[ $line == XXX ]]; then
                if ((state)); then
                    pct=${buf[0]:-0}
                    txt=("${buf[@]:1}")
                    state=0
                else
                    buf=()
                    state=1
                fi
                continue
            fi
            ((state)) && buf+=("$line")
            continue
        fi
        ((rc > 128)) || break # end of the input: the operation is over
        if ((resized)); then
            resized=0
            _size
            _chrome "Ctrl-C:$(t "Interrupt")"
            TUI_TITLE=$heading
            _window 9
        else
            FRAME=""
        fi
        [[ $pct =~ ^[0-9]+$ ]] || pct=0
        ((pct > 100)) && pct=100
        spin=$(((spin + 1) % ${#SPIN[@]}))
        _line 2 "${txt[0]:-}" "${K[bold]}"
        _line 4 "  ${txt[2]:-}"
        _at $((WT + 4)) $((WL + 2)) "${K[accent]}${SPIN[spin]}${K[norm]}"
        _line 5 "  ${txt[3]:-}" "${K[dim]}"
        bw=$((IW - 6)); ((bw < 4)) && bw=4
        fill=$((pct * bw / 100))
        printf -v bar '%*s' "$bw" ''
        bar="${K[bar_fill]}${bar:0:fill}${K[bar_empty]}${bar:fill}"
        bar=${bar// /${G[bar]}}
        _at $((WT + 7)) $((WL + 2)) "$bar${K[norm]} $(printf '%3d%%' "$pct")"
        _pad "$(human_duration $((SECONDS - start)))" 10
        _at $((WT + 8)) $((WL + WW - 12)) "${K[border]} ${K[dim]}${REPLY%"${REPLY##*[! ]}"} ${K[border]}"
        _flush
    done
}

gauge_start() { # heading
    exec 8> >(_gauge_loop "$1" 2>/dev/null)
    GAUGE_PID=$!
}

summary_show() { # heading, file
    TUI_TITLE=$1
    _dialog "$(<"$2")" 0 "$(t "Ok")"
    TUI_TITLE=""
    return 0
}

ui_abort() {
    if ((UI)); then
        UI=0
        exec 8>&-
        kill "$GAUGE_PID" 2>/dev/null
        wait "$GAUGE_PID" 2>/dev/null
    fi
    tui_leave
    t "Interrupted." >/dev/tty
}
