# Mail — the HEY-style notmuch workflow, ported from the Emacs front end
# (~/.config/emacs/lisp/hey-notmuch.el). All logic lives in bin/kak-mail; this
# file is buffers and keys. The backend (mbsync, goimapnotify, the post-new
# router, msmtp) is untouched, and the post-new hook calls mail-refresh-all in
# every session so open boxes stay current.
#
#   <space>m m boxes · b jump to a box · c compose · s search · g sync
#
# In any mail buffer `?` lists its keys (the table lives in mail-help).
# Draft:  ' s send  ' k discard  ' f From identity  ' a attach

declare-option -hidden str mail_query
declare-option -hidden bool mail_unthreaded false
declare-option -hidden str-list mail_ids
declare-option -hidden str-list mail_msgs
declare-option -hidden str mail_return_buf
declare-option -hidden str mail_return_id
declare-option -hidden int mail_return_line 1

# Shell helpers shared by the %sh blocks below. Kakoune only exports the
# kak_* variables a block mentions by name, so every block that evals this
# lists the ones the helpers read in a comment.
declare-option -hidden str mail_sh %{
kq() { printf "'%s'" "$(printf %s "$1" | sed "s/'/''/g")"; }
# ids of the rows under every selection, deduplicated, in order
mail_row_ids() {
    eval "set -- $kak_quoted_opt_mail_ids"
    for d in $kak_selections_desc; do
        a=${d%%.*}; b=${d#*,}; b=${b%%.*}
        [ "$a" -gt "$b" ] && { t=$a; a=$b; b=$t; }
        i=$a
        while [ "$i" -le "$b" ]; do eval "printf '%s\n' \"\${$i}\""; i=$((i + 1)); done
    done | awk 'NF && !seen[$0]++'
}
# the message under the cursor in a thread buffer
mail_msg_at() {
    id=
    eval "set -- $kak_quoted_opt_mail_msgs"
    for m; do [ "${m%%:*}" -le "$kak_cursor_line" ] && id=${m#*:}; done
    [ -n "$id" ] && printf 'id:%s\n' "$id"
}
mail_targets() {
    if [ "$kak_opt_filetype" = mail-thread ]; then mail_msg_at; else mail_row_ids; fi
}
# replace the buffer with FILE's contents (and delete FILE)
mail_fill() {
    printf 'set-option buffer readonly false\n'
    printf 'execute-keys -draft %s\n' "$(kq "%|cat $1; rm -f $1<ret>")"
    printf 'set-option buffer readonly true\n'
}
}

# ─────────────────────────────── boxes ───────────────────────────────

define-command mail -docstring 'open the mail boxes' %{
    edit -scratch *mail*
    set-option buffer filetype mail-boxes
    mail-boxes-render
    execute-keys gg
}

define-command -hidden mail-boxes-render %{
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        f=$(mktemp "${TMPDIR:-/tmp}/kak-mail.XXXXXX")
        if err=$(kak-mail boxes 2>&1 >"$f"); then mail_fill "$f"
        else rm -f "$f"; printf 'fail %s\n' "$(kq "$err")"; fi
    }
}

define-command -hidden mail-boxes-open %{
    evaluate-commands -save-regs a %{
        execute-keys -draft 'x"ay'
        evaluate-commands %sh{
            eval "$kak_opt_mail_sh"
            name=$(printf %s "$kak_reg_a" | cut -c5-16 | sed 's/ *$//')
            [ -n "$name" ] && printf 'mail-box %s\n' "$(kq "$name")"
        }
    }
}

# ─────────────────────────────── lists ───────────────────────────────

define-command mail-box -params 1 -docstring 'mail-box <box name|notmuch query>: list it' %{
    mail-list-open %arg{1} false
}

define-command mail-search -docstring 'list the threads matching a notmuch query' %{
    prompt 'notmuch search: ' %{ mail-box %val{text} }
}

define-command -hidden -params 2 mail-list-open %{
    edit -scratch "*mail:%arg{1}*"
    set-option buffer filetype mail-list
    set-option buffer mail_query %arg{1}
    set-option buffer mail_unthreaded %arg{2}
    mail-list-render
    execute-keys gg
}

define-command -hidden mail-list-render %{
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        f=$(mktemp "${TMPDIR:-/tmp}/kak-mail.XXXXXX")
        flag=; [ "$kak_opt_mail_unthreaded" = true ] && flag=--unthreaded
        if out=$(kak-mail list --out "$f" $flag "$kak_opt_mail_query" 2>&1); then
            printf '%s\n' "$out"
            mail_fill "$f"
        else rm -f "$f"; printf 'fail %s\n' "$(kq "$out")"; fi
    }
}

# After an action: land on the row after ID if it is still listed (it was
# acted on in place), else stay on LINE (it left, and the next row slid up).
define-command -hidden -params 2 mail-advance %{
    evaluate-commands %sh{
        id=$1 line=$2
        eval "set -- $kak_quoted_opt_mail_ids"
        n=$# k=0 target=
        for i; do k=$((k + 1)); [ "$i" = "$id" ] && { target=$((k + 1)); break; }; done
        [ -z "$target" ] && target=$line
        [ "$target" -gt "$n" ] && target=$n
        [ "$target" -lt 1 ] && target=1
        printf 'execute-keys %sg\n' "$target"
    }
}

# ─────────────────────────────── thread ───────────────────────────────

define-command -hidden mail-open %{
    evaluate-commands %sh{
        # $kak_quoted_opt_mail_ids $kak_selections_desc
        eval "$kak_opt_mail_sh"
        id=$(kak_selections_desc="$kak_cursor_line.1,$kak_cursor_line.1" mail_row_ids | head -1)
        [ -z "$id" ] && { echo "fail 'mail: no message on this line'"; exit; }
        printf 'set-option global mail_return_buf %s\n' "$(kq "$kak_bufname")"
        printf 'set-option global mail_return_id %s\n' "$(kq "$id")"
        printf 'set-option global mail_return_line %s\n' "$kak_cursor_line"
        printf 'mail-thread %s\n' "$(kq "$id")"
    }
}

define-command mail-thread -params 1 -docstring 'mail-thread <notmuch query>: read a thread' %{
    edit -scratch *mail-thread*
    set-option buffer filetype mail-thread
    set-option buffer mail_query %arg{1}
    mail-thread-render
    execute-keys gg
}

define-command -hidden mail-thread-render %{
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        f=$(mktemp "${TMPDIR:-/tmp}/kak-mail.XXXXXX")
        if out=$(kak-mail show --out "$f" "$kak_opt_mail_query" 2>&1); then
            printf '%s\n' "$out"
            mail_fill "$f"
        else rm -f "$f"; printf 'fail %s\n' "$(kq "$out")"; fi
    }
}

define-command -hidden mail-back %{
    try %{
        buffer %opt{mail_return_buf}
        mail-list-render
        mail-advance %opt{mail_return_id} %opt{mail_return_line}
    } catch %{ mail }
}

define-command -hidden -params 1 mail-thread-jump %{
    evaluate-commands %sh{
        # $kak_cursor_line
        dir=$1
        eval "set -- $kak_quoted_opt_mail_msgs"
        prev= next=
        for m; do
            l=${m%%:*}
            [ "$l" -lt "$kak_cursor_line" ] && prev=$l
            [ "$l" -gt "$kak_cursor_line" ] && [ -z "$next" ] && next=$l
        done
        [ "$dir" = next ] && t=$next || t=$prev
        [ -n "$t" ] && printf 'execute-keys %sgvt\n' "$t"
    }
}

# Links and attachments of the message under the cursor (in a list: the
# thread's newest). Both open through url_open_cmd (commands.kak), the same
# opener `gu` uses — xdg-open here, so http(s) reaches bin/browser-open.
define-command mail-links -docstring 'pick a link in this message and open it' %{
    evaluate-commands %sh{
        # $kak_quoted_opt_mail_ids $kak_selections_desc $kak_cursor_line $kak_quoted_opt_mail_msgs $kak_opt_filetype
        eval "$kak_opt_mail_sh"
        t=$(mail_targets | head -1)
        [ -z "$t" ] && { echo "fail 'mail: no message here'"; exit; }
        printf 'prompt -menu -shell-script-candidates %s %s %%{ mail-open-with %%val{text} }\n' \
            "$(kq "kak-mail links '$t'")" "$(kq 'link: ')"
    }
}

define-command mail-attachments -docstring 'pick an attachment: save to ~/Downloads and open it' %{
    evaluate-commands %sh{
        # $kak_quoted_opt_mail_ids $kak_selections_desc $kak_cursor_line $kak_quoted_opt_mail_msgs $kak_opt_filetype
        eval "$kak_opt_mail_sh"
        t=$(mail_targets | head -1)
        [ -z "$t" ] && { echo "fail 'mail: no message here'"; exit; }
        [ -z "$(kak-mail attachments "$t" 2>/dev/null)" ] && { echo "fail 'mail: no attachments'"; exit; }
        printf 'prompt -menu -shell-script-candidates %s %s %%{ mail-attachment-get %s %%val{text} }\n' \
            "$(kq "kak-mail attachments '$t'")" "$(kq 'attachment: ')" "$(kq "$t")"
    }
}

define-command -hidden -params 2 mail-attachment-get %{
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        if p=$(kak-mail save "$1" "${2%%:*}" 2>&1); then
            printf 'mail-open-with %s\necho %s\n' "$(kq "$p")" "$(kq "saved $p")"
        else printf 'fail %s\n' "$(kq "$p")"; fi
    }
}

define-command -hidden -params 1 mail-open-with %{
    nop %sh{
        set -- "$1"
        ( eval "$(printf "$kak_opt_url_open_cmd" '"$1"')" ) >/dev/null 2>&1 </dev/null &
    }
}

# ─────────────────────────────── refresh / sync ───────────────────────────────

define-command mail-refresh -docstring 'refresh this mail buffer' %{
    evaluate-commands %sh{
        case $kak_opt_filetype in
            mail-boxes) echo mail-boxes-render ;;
            mail-list) echo mail-list-render ;;
            mail-thread) echo mail-thread-render ;;
        esac
    }
}

# Boxes and lists only: re-rendering a thread would mark it read again.
define-command mail-refresh-all -docstring 'refresh every open mail box and list' %{
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        eval "set -- $kak_quoted_buflist"
        for b; do
            case $b in '*mail*'|'*mail:'*) printf 'evaluate-commands -buffer %s mail-refresh\n' "$(kq "$b")" ;; esac
        done
    }
}

define-command mail-sync -docstring 'fetch mail now (mbsync + notmuch new)' %{
    nop %sh{
        (
            if mail-sync >/dev/null 2>&1; then msg='mail: synced'; else msg='mail: sync failed — see ~/.local/state/hey-mail/sync.log'; fi
            printf "evaluate-commands -client %s %%{ mail-refresh-all; echo '%s' }\n" "$kak_client" "$msg" | kak -p "$kak_session"
        ) >/dev/null 2>&1 </dev/null &
    }
    echo 'mail: syncing…'
}

# ─────────────────────────────── HEY actions ───────────────────────────────

define-command -hidden -params 1..2 mail-hey %{
    evaluate-commands %sh{
        # $kak_quoted_opt_mail_ids $kak_selections_desc $kak_cursor_line $kak_quoted_opt_mail_msgs $kak_opt_filetype
        eval "$kak_opt_mail_sh"
        targets=$(mail_targets)
        [ -z "$targets" ] && { echo "fail 'mail: nothing selected'"; exit; }
        first=$(printf '%s\n' "$targets" | head -1)
        action=$1 arg=$2
        set --
        [ -n "$arg" ] && set -- --arg "$arg"
        if out=$(printf '%s\n' "$targets" | xargs -d '\n' kak-mail hey "$action" "$@" 2>&1); then
            printf 'mail-refresh-all\n'
            if [ "$kak_opt_filetype" = mail-list ]; then
                printf 'mail-advance %s %s\n' "$(kq "$first")" "$kak_cursor_line"
            fi
            printf 'echo %s\n' "$(kq "$out")"
        else printf 'fail %s\n' "$(kq "$out")"; fi
    }
}

define-command -hidden mail-sender %{
    evaluate-commands %sh{
        # $kak_quoted_opt_mail_ids $kak_selections_desc $kak_cursor_line $kak_quoted_opt_mail_msgs $kak_opt_filetype
        eval "$kak_opt_mail_sh"
        t=$(mail_targets | head -1)
        [ -z "$t" ] && { echo "fail 'mail: nothing selected'"; exit; }
        if a=$(kak-mail hey sender "$t" 2>&1); then printf 'mail-list-open %s true\n' "$(kq "from:$a")"
        else printf 'fail %s\n' "$(kq "$a")"; fi
    }
}

# <tab>/<c-n> cycles the presets; anything `date -d` reads is accepted too:
# "fri 14:00", "3 days", "2026-10-05 9am", "+2 hours", "next month".
define-command -hidden mail-bubble-prompt %{
    prompt -shell-script-candidates %{
        printf '%s\n' 'tomorrow 9am' 'today 18:00' 'saturday 9am' 'next monday 9am' '3 days' 'next month'
    } 'bubble up when? (tab: presets · or fri 14:00, 3 days, 2026-10-05 9am): ' %{ mail-hey bubble %val{text} }
}

declare-user-mode hey
map global hey i ':mail-hey screen-in<ret>'   -docstring 'screen in → Imbox'
map global hey f ':mail-hey feed<ret>'        -docstring 'move sender to The Feed'
map global hey p ':prompt "Paper Trail category: " %{ mail-hey papertrail %val{text} }<ret>' -docstring 'move sender to Paper Trail'
map global hey o ':mail-hey screen-out<ret>'  -docstring 'screen out (trash, forever)'
map global hey u ':mail-hey unscreen<ret>'    -docstring 'undo screening (back to Screener)'
map global hey s ':mail-sender<ret>'          -docstring 'everything from this sender'
map global hey l ':mail-hey reply-later<ret>' -docstring 'reply later'
map global hey a ':mail-hey set-aside<ret>'   -docstring 'set aside'
map global hey c ':mail-hey clear<ret>'       -docstring 'clear from the piles'
map global hey z ':mail-bubble-prompt<ret>'  -docstring 'bubble up later…'
map global hey A ':prompt "Autofile this sender as: " %{ mail-hey autofile %val{text} }<ret>' -docstring 'autofile sender under a label'
map global hey R ':prompt -menu -shell-script-candidates %{ printf "30\n90\n730\n" } "Recycle after (days): " %{ mail-hey recycle %val{text} }<ret>' -docstring 'recycle sender after N days'
map global hey g ':mail-sync<ret>'            -docstring 'sync now'

# ─────────────────────────────── compose ───────────────────────────────

define-command mail-compose -params 1 -docstring 'mail-compose new|reply|replyall|forward' %{
    evaluate-commands %sh{
        # $kak_quoted_opt_mail_ids $kak_selections_desc $kak_cursor_line $kak_quoted_opt_mail_msgs $kak_opt_filetype
        eval "$kak_opt_mail_sh"
        set -- "$1"
        if [ "$1" != new ]; then
            t=$(mail_targets | head -1)
            [ -z "$t" ] && { echo "fail 'mail: no message here'"; exit; }
            set -- "$1" "$t"
        fi
        if p=$(kak-mail compose "$@" 2>&1); then
            printf 'edit %s\n' "$(kq "$p")"
            printf "try %%{ execute-keys 'gg/^To: \$<ret>gl' } catch %%{ execute-keys 'gg/^\$<ret>j' }\n"
        else printf 'fail %s\n' "$(kq "$p")"; fi
    }
}

define-command -hidden mail-draft-setup %{
    map buffer local s ':mail-send<ret>'    -docstring 'send'
    map buffer local k ':mail-discard<ret>' -docstring 'discard draft'
    map buffer local f ':mail-from<ret>'    -docstring 'From identity'
    map buffer local a ':mail-attach<ret>'  -docstring 'attach a file'
    mail-prompt-keys
}
hook global BufCreate .*/kak-mail/drafts/[^/]+\.eml mail-draft-setup

define-command mail-send -docstring 'send this draft' %{
    write
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        if out=$(kak-mail send "$kak_buffile" 2>&1); then
            printf 'delete-buffer\nmail-refresh-all\necho %s\n' "$(kq "$out")"
        else printf 'fail %s\n' "$(kq "$out")"; fi
    }
}

define-command mail-discard -docstring 'delete this draft' %{
    nop %sh{ rm -f "$kak_buffile" }
    delete-buffer!
}

define-command -hidden -params 3 mail-draft-header %{
    write
    evaluate-commands %sh{
        eval "$kak_opt_mail_sh"
        if out=$(kak-mail header "$kak_buffile" "$@" 2>&1); then echo 'edit!'
        else printf 'fail %s\n' "$(kq "$out")"; fi
    }
}

define-command mail-from -docstring 'pick the From identity' %{
    prompt -menu -shell-script-candidates 'kak-mail identities' 'From: ' %{ mail-draft-header set From %val{text} }
}

define-command mail-attach -docstring 'attach a file to this draft' %{
    prompt -file-completion 'Attach: ' %{ mail-draft-header add Attach %val{text} }
}

# ─────────────────────────────── keys & faces ───────────────────────────────
# Every key below is buffer-owned (map buffer, set when the mail buffer is
# shown) except the <space>m launcher. `?` in a mail buffer lists that
# buffer's keys; the modes (H hey…, b boxes…, ' in a draft) list their own.

declare-user-mode mail
declare-user-mode mail-jump
evaluate-commands %sh{ command -v kak-mail >/dev/null 2>&1 && kak-mail boxes --maps }

map global user m ':enter-user-mode mail<ret>' -docstring 'mail…'
map global mail m ':mail<ret>'                        -docstring 'boxes'
map global mail b ':enter-user-mode mail-jump<ret>'   -docstring 'jump to a box…'
map global mail c ':mail-compose new<ret>'            -docstring 'compose'
map global mail s ':mail-search<ret>'                 -docstring 'search'
map global mail g ':mail-sync<ret>'                   -docstring 'sync now'

define-command -hidden mail-help %{
    evaluate-commands %sh{
        case $kak_opt_filetype in
        mail-boxes) printf '%s\n' "info -title 'mail: boxes' %{<ret>  open the box on this line
b      jump to a box by letter
u      refresh counts
c      compose     G  sync now
?      this help}" ;;
        mail-list) printf '%s\n' "info -title 'mail: list' %{<ret>  read the thread
r / R  reply / reply all     F  forward
a      archive
H      hey… (screen in/out, feed, piles, bubble up…)
o      open a link           A  save + open an attachment
u      refresh               G  sync now
c      compose               b  jump to a box
q      back to the boxes     ?  this help
select several rows (x, J, %) to act on all of them}" ;;
        mail-thread) printf '%s\n' "info -title 'mail: thread' %{r / R      reply / reply all to the message under the cursor
F          forward it
<c-n>/<c-p> next / previous message
o          open a link           A  save + open an attachment
gu         open the URL under the cursor
H          hey… (screen in/out, feed, piles, bubble up…)
c          compose               G  sync now
b          jump to a box
q          back to the list      ?  this help}" ;;
        esac
    }
}

# Mail prompts (links, attachments, From, recycle days, bubble presets) step
# through their options with <c-n>/<c-p> as well as <tab>/<s-tab>. Buffer-
# scoped, so prompts elsewhere keep <c-n>/<c-p> as history.
define-command -hidden mail-prompt-keys %{
    map buffer prompt <c-n> <tab>
    map buffer prompt <c-p> <s-tab>
}

# Header, address and quote colours for threads and drafts. Kakoune's stock
# `mail` filetype module is not part of this config, so it is not relied on.
add-highlighter shared/kak-mail group
add-highlighter shared/kak-mail/ regex ^(From|To|Cc|Bcc|Subject|Reply-To|In-Reply-To|References|Date|Attach|Tags):(\N*)$ 1:keyword 2:attribute
add-highlighter shared/kak-mail/ regex <[^<>@\s]+@[^<>\s]+> 0:string
add-highlighter shared/kak-mail/ regex ^>\N*$ 0:comment
add-highlighter shared/kak-mail/ regex ^--\ \n\N* 0:comment

hook global WinSetOption filetype=mail-(boxes|list|thread) %{
    map buffer normal b ':enter-user-mode mail-jump<ret>' -docstring 'jump to a box'
    map buffer normal G ':mail-sync<ret>'                 -docstring 'sync'
    map buffer normal c ':mail-compose new<ret>'          -docstring 'compose'
    map buffer normal ? ':mail-help<ret>'                 -docstring 'keys'
    mail-prompt-keys
}

hook global WinSetOption filetype=mail-boxes %{
    map buffer normal <ret> ':mail-boxes-open<ret>' -docstring 'open box'
    map buffer normal u ':mail-refresh<ret>'        -docstring 'refresh'
    add-highlighter window/mail-boxes group
    add-highlighter window/mail-boxes/ regex '^ (\S) ' 1:keyword
    add-highlighter window/mail-boxes/ regex ' ([1-9]\d*)$' 1:value
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/mail-boxes }
}

hook global WinSetOption filetype=mail-(list|thread) %{
    map buffer normal r ':mail-compose reply<ret>'    -docstring 'reply'
    map buffer normal R ':mail-compose replyall<ret>' -docstring 'reply all'
    map buffer normal F ':mail-compose forward<ret>'  -docstring 'forward'
    map buffer normal H ':enter-user-mode hey<ret>'   -docstring 'hey…'
    map buffer normal o ':mail-links<ret>'            -docstring 'open a link'
    map buffer normal A ':mail-attachments<ret>'      -docstring 'save + open an attachment'
}

hook global WinSetOption filetype=mail-list %{
    map buffer normal <ret> ':mail-open<ret>'        -docstring 'read thread'
    map buffer normal a ':mail-hey archive<ret>'     -docstring 'archive'
    map buffer normal u ':mail-refresh<ret>'         -docstring 'refresh'
    map buffer normal q ':mail<ret>'                 -docstring 'boxes'
    add-highlighter window/mail-list group
    add-highlighter window/mail-list/ regex '^.{10}' 0:comment
    add-highlighter window/mail-list/ regex '\[([^\]\n]*)\]$' 1:keyword
    add-highlighter window/mail-list/ regex '^[^\n]*\[[^\]\n]*\bunread\b[^\]\n]*\]$' 0:+b
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/mail-list }
}

hook global WinSetOption filetype=mail-thread %{
    map buffer normal q ':mail-back<ret>'              -docstring 'back to the list'
    map buffer normal <c-n> ':mail-thread-jump next<ret>' -docstring 'next message'
    map buffer normal <c-p> ':mail-thread-jump prev<ret>' -docstring 'previous message'
    add-highlighter window/mail-thread group
    add-highlighter window/mail-thread/ ref kak-mail
    add-highlighter window/mail-thread/ regex '^━+$' 0:comment
    add-highlighter window/mail-thread/ regex '^\[attachment \d+: [^\n]*\]$' 0:string
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/mail-thread }
}

hook global WinSetOption filetype=mail %{
    add-highlighter window/kak-mail ref kak-mail
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/kak-mail }
}
