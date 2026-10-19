provide-module html %{
	add-highlighter shared/html regions
	add-highlighter shared/html/comment region <!-- --> fill comment
	add-highlighter shared/html/anchor region '<a(?:\s+[^>]*)?>\K' '(?=</a>)' fill ts_markup_link_label
	add-highlighter shared/html/strong region '<strong(?:\s+[^>]*)?>\K' '(?=</strong>)' fill ts_markup_bold
	add-highlighter shared/html/em region '<em(?:\s+[^>]*)?>\K' '(?=</em>)' fill ts_markup_italic
	add-highlighter shared/html/strike region '<s(?:\s+[^>]*)?>\K' '(?=</s>)' fill ts_markup_strikethrough
	add-highlighter shared/html/code default-region group
	add-highlighter shared/html/code/ regex '&(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]+|#x[0-9a-fA-F]+);' 0:ts_string_special_symbol
	add-highlighter shared/html/tag region < > regions
	add-highlighter shared/html/tag/dquote region '"' (?<!\\)(\\\\)*" group
	add-highlighter shared/html/tag/squote region "'" "'" group
	add-highlighter shared/html/tag/dquote/ fill string
	add-highlighter shared/html/tag/squote/ fill string
	add-highlighter shared/html/tag/dquote/ regex '(?<=href=)"([\w+/._-]*)"' 1:ts_markup_link_url
	add-highlighter shared/html/tag/dquote/ regex '(?<=src=)"([\w+/._-]*)"' 1:ts_markup_link_url
	add-highlighter shared/html/tag/squote/ regex "(?<=href=)'([\w+/._-]*)'" 1:ts_markup_link_url
	add-highlighter shared/html/tag/squote/ regex "(?<=src=)'([\w+/._-]*)'" 1:ts_markup_link_url
	add-highlighter shared/html/tag/base default-region group
	add-highlighter shared/html/tag/base/ regex \b([a-zA-Z0-9_-]+)=? 1:attribute
	add-highlighter shared/html/tag/base/ regex </?(\w+) 1:ts_tag
	add-highlighter shared/html/tag/base/ regex <(!DOCTYPE(\h+\w+)+) 1:ts_constant
	add-highlighter shared/html/tag/base/ regex <(!doctype(\h+\w+)+) 1:ts_constant
	add-highlighter shared/html/tag/base/ regex [<|>|</|\\>|<!] 0:ts_punctuation_bracket
	add-highlighter shared/html/tag/base/ regex [=] 0:ts_punctuation_delimiter
}
