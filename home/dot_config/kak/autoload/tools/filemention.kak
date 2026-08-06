# filemention — type '@' in a prose buffer to pick a file and insert its
# path as an "@mention", à la filemention.nvim.
#
#   @            -> opens the picker, inserts  @relative/path
#   [@           -> opens the picker, inserts  [@basename](relative/path)
#
# Paths are relative to %opt{root_path} (see root.kak). The picker is the
# native completion menu fed by your configured finder (see find.kak), so
# it stays inline in the editor. Aborting (<esc>) leaves the literal '@'
# untouched, so the trigger is non-destructive.

# Filetypes the '@' trigger is active in. Plain text has no filetype in
# Kakoune; add buffer-specific filetypes here as needed.
declare-option -docstring 'filetypes where the @ file-mention trigger is active' \
  str-list filemention_filetypes markdown asciidoc git-commit

# Set per-trigger to 'plain' or 'link', read back when the pick is accepted.
declare-option -hidden str filemention_variant plain
# "line.column" of the just-typed '@' (selection-desc / byte coordinates),
# captured before leaving insert so placement never depends on cursor drift.
declare-option -hidden str filemention_at

# Install/remove the window-local trigger as the filetype changes, so we
# never shell out on '@' in code buffers.
hook global WinSetOption filetype=.* %{
  remove-hooks window filemention
  evaluate-commands %sh{
    case " $kak_opt_filemention_filetypes " in
      *" $kak_opt_filetype "*)
        echo "hook -group filemention window InsertChar '@' filemention-trigger" ;;
    esac
  }
}

define-command -hidden filemention-trigger %{
  set-option window filemention_variant plain
  # InsertChar fired: the '@' is in the buffer and the cursor sits right
  # after it. Capture the '@' byte position from the insert cursor.
  set-option window filemention_at %sh{ printf '%s.%s' "$kak_cursor_line" "$((kak_cursor_column - 1))" }
  execute-keys '<esc>'

  # In normal mode now: a '[' immediately before '@' selects the
  # markdown-link form.
  evaluate-commands %sh{
    line=${kak_opt_filemention_at%.*}
    before=$(( ${kak_opt_filemention_at#*.} - 1 ))
    if [ "$before" -ge 1 ]; then
      printf 'try %%{ evaluate-commands -draft %%{ select %s.%s,%s.%s; execute-keys %%§<a-k>\\[<ret>§; set-option window filemention_variant link } }\n' \
        "$line" "$before" "$line" "$before"
    fi
  }

  prompt 'mention: ' -menu -shell-script-candidates %{
    cd "$kak_opt_root_path" 2>/dev/null && eval "$kak_opt_find_command $kak_quoted_opt_find_args"
  } -on-abort %{
    # Non-destructive: keep the literal '@', resume insert right after it.
    evaluate-commands %sh{ printf 'select %s,%s' "$kak_opt_filemention_at" "$kak_opt_filemention_at" }
    execute-keys 'a'
  } %{
    evaluate-commands -save-regs '"' %{
      set-register '"' %sh{
        path="$kak_text"
        if [ "$kak_opt_filemention_variant" = link ]; then
          printf '%s](%s)' "${path##*/}" "$path"
        else
          printf '%s' "$path"
        fi
      }
      # Re-select the '@' deterministically, then append the mention after
      # it and stay in insert so typing continues naturally.
      evaluate-commands %sh{ printf 'select %s,%s' "$kak_opt_filemention_at" "$kak_opt_filemention_at" }
      execute-keys 'a<c-r>"'
    }
  }
}
