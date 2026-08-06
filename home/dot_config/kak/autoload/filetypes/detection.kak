# --------------------------------
# Treesitter Filetypes
# --------------------------------

# --- Common / Web ---
hook global BufCreate .*[.](astro) %{ set-option buffer filetype astro }
hook global BufCreate .*\.((z|ba|c|k|mk)?(sh(rc|_profile|env)?|profile)) %{ set-option buffer filetype bash }
# Mirrors helix env globs: .env .env.* .envrc .envrc.* _environment* .bazeliskrc
# .gitlab-ci-local-env  (plus .dev.vars / .dev.vars.* for Cloudflare Workers)
hook global BufCreate (.*/)?(\.env(\.[^/]*)?|\.envrc(\.[^/]*)?|_environment([.-][^/]*)?|\.dev\.vars(\.[^/]*)?|\.bazeliskrc|\.gitlab-ci-local-env) %{ set-option buffer filetype env }
hook global BufCreate .*[.](c|h) %{ set-option buffer filetype c }
hook global BufCreate .*\.(cc|cpp|cxx|C|hh|hpp|hxx|H|ipp|tpp|ixx|txx|ino|cu|cuh|cppm|inl|ii)$ %{ set-option buffer filetype cpp }
hook global BufCreate .*[.](cs|csx|cake) %{ set-option buffer filetype csharp }
hook global BufCreate .*[.](css) %{ set-option buffer filetype css }
hook global BufCreate .*[.](csv) %{ set-option buffer filetype csv }
hook global BufCreate .*[.](dart) %{ set-option buffer filetype dart }
hook global BufCreate .*[.](diff|patch) %{ set-option buffer filetype diff }
hook global BufCreate .*[.]Dockerfile %{ set-option buffer filetype dockerfile }
hook global BufCreate .*[.](ex|exs) %{ set-option buffer filetype elixir }
hook global BufCreate .*[.](elm) %{ set-option buffer filetype elm }
hook global BufCreate .*[.](erl|hrl) %{ set-option buffer filetype erlang }
hook global BufCreate .*[.](fish) %{ set-option buffer filetype fish }
hook global BufCreate .*[.](gleam) %{ set-option buffer filetype gleam }
hook global BufCreate .*[.](go) %{ set-option buffer filetype go }
hook global BufCreate .*[.](graphqls?) %{ set-option buffer filetype graphql }
hook global BufCreate .*[.](html?|htm|shtml|xhtml) %{ set-option buffer filetype html }
hook global BufCreate .*[.](hurl) %{ set-option buffer filetype hurl }
hook global BufCreate .*[.][cm]?(jsx) %{ set-option buffer filetype jsx }
hook global BufCreate .*[.][cm]?(js)$ %{ set-option buffer filetype javascript }
hook global BufCreate .*[.](json) %{ set-option buffer filetype json }
hook global BufCreate .*[.](jsonc) %{ set-option buffer filetype jsonc }
hook global BufCreate .*[/\\]([tj]sconfig|\.?devcontainer)(\.json)?$ %{ set-option buffer filetype jsonc }
hook global BufCreate .*[/\\]\.vscode[/\\].*\.json$ %{ set-option buffer filetype jsonc }
hook global BufCreate .*[.](json5) %{ set-option buffer filetype json5 }
hook global BufCreate .*[.](lua) %{ set-option buffer filetype lua }
hook global BufCreate .*[.](md|markdown|mkd|mkdn|mdwn|mdown|mdx) %{ set-option buffer filetype markdown }
hook global BufCreate .*[.](php|inc|phtml) %{ set-option buffer filetype php }
hook global BufCreate .*\.blade\.php$ %{ set-option buffer filetype blade }
hook global BufCreate .*[.](py|pyi|pyw) %{ set-option buffer filetype python }
hook global BufCreate .*(([.](rb))|(Gemfile|[.]gemspec)|(Rakefile|[.]rake)) %{ set-option buffer filetype ruby }
hook global BufCreate .*[.](rs) %{ set-option buffer filetype rust }
hook global BufCreate .*[.](scss) %{ set-option buffer filetype scss }
hook global BufCreate .*[.](svelte) %{ set-option buffer filetype svelte }
hook global BufCreate .*[.](swift) %{ set-option buffer filetype swift }
hook global BufCreate .*[.](toml) %{ set-option buffer filetype toml }
hook global BufCreate .*[.](tsx) %{ set-option buffer filetype tsx }
hook global BufCreate .*[.][cm]?(ts)$ %{ set-option buffer filetype typescript }
hook global BufCreate .*[.](vue) %{ set-option buffer filetype vue }
hook global BufCreate .*[.](xml|xsl|xslt|xsd|svg) %{ set-option buffer filetype xml }
hook global BufCreate .*[.](ya?ml) %{ set-option buffer filetype yaml }

# --- Systems / DevOps ---
hook global BufCreate .*[.](awk|gawk|nawk|mawk) %{ set-option buffer filetype awk }
hook global BufCreate .*[.](cmake|CMakeLists\.txt) %{ set-option buffer filetype cmake }
hook global BufCreate .*[.](cue) %{ set-option buffer filetype cue }
hook global BufCreate .*(/?[mM]akefile|\.mk|\.make) %{ set-option buffer filetype make }
hook global BufCreate .*[.](nix) %{ set-option buffer filetype nix }
hook global BufCreate .*[.](nu) %{ set-option buffer filetype nu }
hook global BufCreate .*[.](hcl|tf|nomad) %{ set-option buffer filetype hcl }
hook global BufCreate .*[.](tfvars) %{ set-option buffer filetype tfvars }
hook global BufCreate .*[.](proto) %{ set-option buffer filetype protobuf }
hook global BufCreate .*[.](zig|zon) %{ set-option buffer filetype zig }
hook global BufCreate .*[.](sol) %{ set-option buffer filetype solidity }
hook global BufCreate .*[.](wgsl) %{ set-option buffer filetype wgsl }
hook global BufCreate .*[.](ini|cfg) %{ set-option buffer filetype ini }
hook global BufCreate .*[.](tcl) %{ set-option buffer filetype tcl }

# --- Functional / Academic ---
hook global BufCreate .*[.](hs|hs-boot|hsc) %{ set-option buffer filetype haskell }
hook global BufCreate .*[.](purs) %{ set-option buffer filetype purescript }
hook global BufCreate .*[.](ml) %{ set-option buffer filetype ocaml }
hook global BufCreate .*[.](mli) %{ set-option buffer filetype ocaml-interface }
hook global BufCreate .*[.](clj|cljs|cljc|edn) %{ set-option buffer filetype clojure }
hook global BufCreate .*[.](ss|scm|sld) %{ set-option buffer filetype scheme }
hook global BufCreate .*[.](fnl) %{ set-option buffer filetype fennel }
hook global BufCreate .*[.](el) %{ set-option buffer filetype elisp }
hook global BufCreate .*[.](scala|sbt|sc) %{ set-option buffer filetype scala }
hook global BufCreate .*[.](kt|kts) %{ set-option buffer filetype kotlin }
hook global BufCreate .*[.](java|jav) %{ set-option buffer filetype java }
hook global BufCreate .*[.](jl) %{ set-option buffer filetype julia }
hook global BufCreate .*[.](r|R) %{ set-option buffer filetype r }
hook global BufCreate .*[.](nim|nims|nimble) %{ set-option buffer filetype nim }

# --- Other Languages ---
hook global BufCreate .*[.](ada|adb|ads) %{ set-option buffer filetype ada }
hook global BufCreate .*[.](cr) %{ set-option buffer filetype crystal }
hook global BufCreate .*[.](d|dd) %{ set-option buffer filetype d }
hook global BufCreate .*[.](f|for|f90|f95|f03|F|F90|F95|F03) %{ set-option buffer filetype fortran }
hook global BufCreate .*[.](fs|fsx|fsi) %{ set-option buffer filetype fsharp }
hook global BufCreate .*[.](gd) %{ set-option buffer filetype gdscript }
hook global BufCreate .*[.](gradle|groovy|[Jj]enkinsfile) %{ set-option buffer filetype groovy }
hook global BufCreate .*[.](ha) %{ set-option buffer filetype hare }
hook global BufCreate .*[.](odin) %{ set-option buffer filetype odin }
hook global BufCreate .*[.](pas|pp|lpr) %{ set-option buffer filetype pascal }
hook global BufCreate .*[.](ps1|psm1|psd1) %{ set-option buffer filetype powershell }
hook global BufCreate .*[.](rkt|rktd) %{ set-option buffer filetype racket }
hook global BufCreate .*[.](res) %{ set-option buffer filetype rescript }
hook global BufCreate .*[.](slang) %{ set-option buffer filetype slang }
hook global BufCreate .*[.](typst|typ) %{ set-option buffer filetype typst }
hook global BufCreate .*[.](v|vh) %{ set-option buffer filetype verilog }
hook global BufCreate .*[.](vhd|vhdl) %{ set-option buffer filetype vhdl }

# --- Markup / Data ---
hook global BufCreate .*[.](tex|sty|cls) %{ set-option buffer filetype latex }
hook global BufCreate .*[.](org) %{ set-option buffer filetype org }
hook global BufCreate .*[.](bib) %{ set-option buffer filetype bibtex }
hook global BufCreate .*[.](?i)sql %{ set-option buffer filetype sql }
hook global BufCreate .*[.](kdl) %{ set-option buffer filetype kdl }
hook global BufCreate .*[.](dot) %{ set-option buffer filetype dot }
hook global BufCreate .*[.](jsonnet|libsonnet) %{ set-option buffer filetype jsonnet }
hook global BufCreate .*[.](rego) %{ set-option buffer filetype rego }
hook global BufCreate .*[.](nickel|ncl) %{ set-option buffer filetype nickel }

# --- Shader / GPU ---
hook global BufCreate .*[.](glsl|vert|frag|geom|tesc|tese|comp) %{ set-option buffer filetype glsl }
hook global BufCreate .*[.](bicep|bicepparam) %{ set-option buffer filetype bicep }

# --- Template ---
hook global BufCreate .*[.](twig) %{ set-option buffer filetype twig }
hook global BufCreate .*[.](pug|jade) %{ set-option buffer filetype pug }
hook global BufCreate .*[.](jinja|jinja2|j2) %{ set-option buffer filetype jinja }
hook global BufCreate .*[.](eex) %{ set-option buffer filetype eex }
hook global BufCreate .*[.](heex) %{ set-option buffer filetype heex }
hook global BufCreate .*[.](erb) %{ set-option buffer filetype erb }
hook global BufCreate .*[.](templ) %{ set-option buffer filetype templ }
hook global BufCreate .*[.](pest) %{ set-option buffer filetype pest }
hook global BufCreate .*[.](prisma) %{ set-option buffer filetype prisma }

# --- Justfile ---
hook global BufCreate .*(justfile|Justfile|\.justfile) %{ set-option buffer filetype just }

# --- Git ---
hook global BufCreate .*(\.git(config|modules)|git/config) %{ set-option buffer filetype git-config }
hook global BufCreate .*git-rebase-todo %{ set-option buffer filetype git-rebase }
hook global BufCreate .*\.gitattributes %{ set-option buffer filetype git-attributes }
hook global BufCreate .*(COMMIT_EDITMSG|MERGE_MSG|TAG_EDITMSG) %{ set-option buffer filetype git-commit }
hook global BufCreate .*\.gitignore %{ set-option buffer filetype git-ignore }

# --- Ghostty ---
hook global BufCreate .*(ghostty/config) %{ set-option buffer filetype ghostty }

# --- Log / Mail ---
hook global BufCreate .*[.](log) %{ set-option buffer filetype log }
hook global BufCreate .+\.eml %{ set-option buffer filetype mail }

# --- Misc ---
hook global BufCreate .*[.](s) %{ set-option buffer filetype gas }
hook global BufCreate .*[.](m) %{ set-option buffer filetype matlab }
hook global BufCreate .*go\.mod$ %{ set-option buffer filetype gomod }
hook global BufCreate .*[.](task) %{ set-option buffer filetype task }
hook global BufCreate .*[.](liquid) %{ set-option buffer filetype liquid }
hook global BufCreate '\*git_blame\*' %{ set buffer filetype git_blame }
