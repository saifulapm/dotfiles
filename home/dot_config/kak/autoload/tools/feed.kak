# Feed reader — elfeed-kak (github.com/saifulapm/kakfeed), installed by
# run_after_53. The binary emits its own glue (:elfeed, :elfeed-tree, the
# *elfeed* buffer keys); subscriptions are ~/.config/elfeed-kak/config.toml.
evaluate-commands %sh{
    command -v elfeed-kak >/dev/null 2>&1 && elfeed-kak init
}

map global user r ':elfeed<ret>' -docstring 'feeds (elfeed)'

# Additions to the glue's own keys, all buffer-owned: `?` lists the buffer's
# keys, `q` backs out of the entry and tree views, and prompts step through
# options with <c-n>/<c-p> as well as <tab>/<s-tab>.
define-command -hidden feed-help %{
    evaluate-commands %sh{
        case $kak_opt_filetype in
        elfeed) printf '%s\n' "info -title 'feeds: list' %{<ret>  read the entry (marks it read)
b / B  open in browser / in mpv
r / u  mark read / unread     R  mark the whole list read
+ / -  add / remove a tag
s      live filter            S  set filter     c  default filter
= / @  only this feed / this date (again to undo)
z      feed tree
G      update all feeds       V  update feeds in this list
g      redraw                 y  copy Title <link>
d      download enclosure     t / T  rename entry / feed
filters: +tag -tag @2-weeks-ago =feed #20 word
prompts complete with <tab> or <c-n>/<c-p> (tags, feeds, ages)
select several lines to act on all of them}" ;;
        elfeed-entry) printf '%s\n' "info -title 'feeds: entry' %{n / p  next / previous entry
b / B  open in browser / in mpv
r / u  mark read / unread     + / -  add / remove a tag
y      copy Title <link>      d  download enclosure
gu     open the URL under the cursor
g      refresh
s / q  back to the list       ?  this help}" ;;
        elfeed-tree) printf '%s\n' "info -title 'feeds: tree' %{<ret>      list this feed / tag
<tab>      fold / unfold          <s-tab>    fold / unfold all
s          live filter            T  rename feed
G          update all feeds       g  redraw
q          back to the list       ?  this help}" ;;
        esac
    }
}

hook global WinSetOption filetype=elfeed(|-entry|-tree) %{
    map buffer normal ? ':feed-help<ret>' -docstring 'keys'
    map buffer prompt <c-n> <tab>
    map buffer prompt <c-p> <s-tab>
}
hook global WinSetOption filetype=elfeed-(entry|tree) %{
    map buffer normal q ':elfeed<ret>' -docstring 'back to the list'
}
