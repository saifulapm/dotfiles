declare-option -hidden bool base_readonly false

# High-level selection expanding and contracting, based on selection direction
define-command byline-drag-down %{
	evaluate-commands -itersel -no-hooks %{
		try %{
			byline-assert-selection-forwards
			byline-expand-below
		} catch %{
			byline-contract-above
		}
	}
}

define-command byline-drag-up %{
	evaluate-commands -itersel -no-hooks %{
		try %{
			byline-assert-selection-forwards
			byline-contract-below
		} catch %{
			byline-expand-above
		}
	}
}

# Assertions
define-command -hidden byline-assert-selection-reduced %{
	# Selections on blank lines are not considered reduced
	execute-keys -draft "<a-K>^$<ret>"
	# Single-character selections are reduced
	execute-keys -draft "<a-k>\A.{,1}\z<ret>"
}

define-command -hidden byline-assert-selection-forwards %{
	try %{
		# If the selection is just the cursor or blank line
		# , we treat it as being in the forwards
		# direction, and can exit early
		byline-assert-selection-reduced
	} catch %{
		evaluate-commands -no-hooks -draft -save-regs 'ab' %{
			# this "check" requires readonly to be false,
			# so we store its original value before changing it
			set-option buffer base_readonly %opt{readonly}
			# store current cursor pos
			set-register a %val{cursor_byte_offset}
			# force cursor forward
			execute-keys <a-:>
			# store second cursor pos
			set-register b %val{cursor_byte_offset}
			# check whether readonly is enabled
			try %{
  				%opt{base_readonly}
  				# disable temporarily
  				set-option buffer readonly false
			}
			# if the sel faces forward, the cursor hasn't moved
			# So we paste reg a. the pasted content is now selected.
			# We can use <a-k> to check whether it matches register b.
			try %{
				execute-keys %exp{"aP<a-k>%reg{b}<ret>u}
				# only re-enable readme if it was originally on
				try %{
  					%opt{base_readonly}
  					set-option buffer readonly true
				}
			} catch %{
				# clean up the pasted content if the above
				# assertion failed
				execute-keys 'u'
				# only re-enable readme if it was originally on
				try %{
  					%opt{base_readonly}
  					set-option buffer readonly true
				}
				# propogate failure to caller
				fail
			}
		}
	}
}

define-command -hidden byline-assert-selection-full-lines %{
	# Starts at beginning of line
	execute-keys -draft "<a-:><a-;>;<a-k>\A^<ret>"
	# Ends at end of line
	execute-keys -draft "<a-:>;<a-k>$<ret>"
}

# Low-level selection expanding and contracting primitives

define-command -hidden byline-expand-above %{
	try %{
		byline-assert-selection-full-lines
		execute-keys "<a-:><a-;>%val{count}Kx"
	} catch %{
		execute-keys "x<a-:><a-;>"
		evaluate-commands -no-hooks %sh{
			if [ "$kak_count" -gt 1 ]; then
			echo "execute-keys '$((kak_count - 1))Kx'"
			fi
		}
	}
}

define-command -hidden byline-contract-above %{
	try %{
		byline-assert-selection-full-lines
		execute-keys "<a-:><a-;>%val{count}Jx"
	} catch %{
		try %{
			execute-keys "<a-x>"
		} catch %{
			execute-keys "x"
		}
		execute-keys "<a-:><a-;>"
		evaluate-commands -no-hooks %sh{
			if [ "$kak_count" -gt 1 ]; then
			echo "execute-keys '$((kak_count - 1))Jx'"
			fi
		}
	}
}

define-command -hidden byline-expand-below %{
	try %{
		byline-assert-selection-full-lines
		execute-keys "<a-:>%val{count}Jx"
	} catch %{
		execute-keys "x<a-:>"
		evaluate-commands -no-hooks %sh{
			if [ "$kak_count" -gt 1 ]; then
			echo "execute-keys '$((kak_count - 1))Jx'"
			fi
		}
	}
}

define-command -hidden byline-contract-below %{
	try %{
		byline-assert-selection-full-lines
		execute-keys "<a-:>%val{count}Kx"
	} catch %{
		try %{
			execute-keys "<a-x>"
		} catch %{
			execute-keys "x"
		}
		execute-keys "<a-:>"
		evaluate-commands -no-hooks %sh{
			if [ "$kak_count" -gt 1 ]; then
			echo "execute-keys '$((kak_count - 1))Kx'"
			fi
		}
	}
}
