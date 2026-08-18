# cliamp — completions, HAND-WRITTEN on purpose.
#
# `cliamp completion fish` cannot be used. Its generator (urfave/cli's fish
# template) double-formats the script: the template is run through Go's
# fmt a second time, so every literal `%` in the fish source is eaten as a
# format verb and the output comes back as garbage —
#
#   function __%!_(string=cliamp)perform_completion
#   printf "%!s(MISSING)\t%!s(MISSING)\n" "$parts[1]" "$parts[2]"
#   complete -c %! (string=cliamp)-f -a '(__%!_(string=cliamp)perform_completion)'
#
# which fish refuses to parse, and because fish sources this directory on
# every prompt, installing it put a syntax error in front of every command
# the user typed. It was generated into place by run_after_23 for exactly one
# apply on 2026-08-18 and pulled straight back out; that script now validates
# everything it generates with `fish -n` before installing it, so no generator
# can do this again.
#
# The BINARY is fine — only the wrapper template is broken. `--generate-shell-
# completion` is cliamp's real completion protocol and it walks the whole
# subcommand tree correctly (`cliamp playlist --generate-shell-completion` →
# list, create, rename, add, show, …). So this file is upstream's design,
# spelled correctly by hand: it stays DYNAMIC, asking the binary rather than
# hard-coding a verb list that would drift on the next release.
#
# Delete this file and try `cliamp completion fish` again after a cliamp
# upgrade — the day it emits a parseable script, upstream has fixed it.

function __cliamp_perform_completion
    set -l args (commandline -opc)

    # The PARTIAL word is deliberately NOT passed, which is where upstream's
    # template goes wrong for fish. It appends `commandline -ct`, and cliamp
    # then resolves that fragment as a finished subcommand: `cliamp play<TAB>`
    # runs `cliamp play --generate-shell-completion`, which answers with
    # play's OWN subcommands (just `help`) — so the two real candidates,
    # `play` and `playlist`, never appear. Measured, not assumed.
    #
    # fish does not need the fragment: `complete -a` takes the full candidate
    # list and filters it by prefix itself. So we ask for the completions of
    # the last COMPLETE command and let the shell narrow them.
    #
    # $args[2..-1] on a single-element list is empty in fish rather than an
    # error, so this covers bare `cliamp <TAB>` and any depth of subcommand.
    for line in ($args[1] $args[2..-1] --generate-shell-completion 2>/dev/null)
        test -n "$line"; or continue

        # THE OUTPUT FORMAT DEPENDS ON $SHELL. urfave/cli prints bare names
        # under bash, but `name:description` when $SHELL ends in fish or zsh —
        # which is every real session this file runs in:
        #
        #   SHELL=/bin/bash     → setup
        #   SHELL=/usr/bin/fish → setup:interactive wizard to configure remote providers
        #
        # Passed through unsplit, that whole string becomes the completion
        # VALUE, and accepting it types `cliamp setup:interactive\ wizard\ to\
        # configure\ remote\ providers` onto the command line. Splitting on the
        # first colon into fish's own value<TAB>description is what upstream's
        # template intended to do here.
        #
        # -m 1 so a value that itself contains a colon keeps the remainder in
        # its description rather than being cut into three.
        set -l parts (string split -m 1 ":" -- $line)
        if test (count $parts) -eq 2
            printf '%s\t%s\n' $parts[1] $parts[2]
        else
            printf '%s\n' $line
        end
    end
end

# NO `-f`, deliberately, though upstream's template has it. cliamp's primary
# argument is a path — `cliamp ~/Music`, `cliamp *.flac` — and -f would switch
# file completion off entirely, so the verbs would arrive at the cost of the
# thing the command is most often given.
complete -c cliamp -a '(__cliamp_perform_completion)'
