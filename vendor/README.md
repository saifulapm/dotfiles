# vendor/

Third-party source we carry verbatim, pinned by hand.

Everything else third-party is fetched at apply time — packages from
`packages/manifest.toml`, crates and release binaries from the `run_after_09`
/`run_after_10` scripts, source builds from their own `run_after` script.
A tree lands here instead when the upstream ships no package we can consume
on this machine and the code is small enough to read in one sitting.

Nothing here is edited. A local change belongs upstream or in a fork of our
own (that is what `saifulapm/nirisnap` is); a diff against upstream that
lives only in this directory is invisible the day we refresh it.

## try

`try/` — [github.com/tobi/try](https://github.com/tobi/try), MIT.
Dated scratch directories with a fuzzy picker; `~/Sites/tries` here, or
wherever `TRY_PATH` points. The shell side is
`home/dot_config/fish/functions/try.fish`.

| | |
|---|---|
| pinned at | `be56682` (v1.10.1, 2026-08-13) |
| files | `try.rb`, `lib/tui.rb`, `lib/fuzzy.rb` — the whole program |
| needs | `ruby` (manifest, `dev`); no gems, no bundler |

Upstream publishes a `try-cli` gem and a Homebrew tap, neither of which is a
mechanism this repo already has, and its "native binary" needs Spinel built
from source plus an unmerged PR. Three files and the `ruby` package is the
cheaper trade — at the price of refreshing them by hand:

```sh
git clone --depth 1 https://github.com/tobi/try /tmp/try
cp /tmp/try/try.rb vendor/try/try.rb
cp /tmp/try/lib/tui.rb /tmp/try/lib/fuzzy.rb vendor/try/lib/
```

Then re-pin the row above and re-read `try init fish`: `try.fish` is that
snippet with our path baked in, so a change to the generated wrapper has to
be copied across by hand too.
