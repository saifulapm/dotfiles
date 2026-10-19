# Hop Kak
declare-option -hidden str hop_kak_keyset 'fjdkslahgqwertyuiopzxcvbnm'
declare-option -hidden range-specs hop_ranges

define-command hop-kak %{
  evaluate-commands -no-hooks -- %sh{ hop-kak --keyset "$kak_opt_hop_kak_keyset" --sels "$kak_selections_desc" }
}

define-command hop-kak-words %{
  evaluate-commands -draft %{
    execute-keys 'gtGbxs\w+<ret>'
    evaluate-commands -no-hooks -client "%val{client}" -- %sh{ hop-kak --keyset "$kak_opt_hop_kak_keyset" --sels "$kak_selections_desc" }
  }
}
