declare-option -hidden range-specs colorize_ranges
declare-option -hidden int colorize_last_ts 0

define-command colorize -docstring 'Enable color highlighting with auto-update' %{
  try %{ add-highlighter window/colorize ranges colorize_ranges }
  colorize-refresh
  hook -group colorize window NormalIdle .* %{ colorize-update }
  echo 'Color highlighting enabled'
}

define-command colorize-disable -docstring 'Disable color highlighting' %{
  remove-highlighter window/colorize
  remove-hooks window colorize
  set-option window colorize_ranges %val{timestamp}
  set-option window colorize_last_ts 0
  echo 'Color highlighting disabled'
}

define-command -hidden colorize-update %{
  evaluate-commands %sh{
    [ "$kak_timestamp" = "$kak_opt_colorize_last_ts" ] && exit
    printf 'colorize-refresh\n'
  }
}

define-command -hidden colorize-refresh %{
  set-option window colorize_last_ts %val{timestamp}
  set-option window colorize_ranges %val{timestamp}
  evaluate-commands -draft %{
    execute-keys '%'

    # Hex 6-digit: #RRGGBB
    evaluate-commands -draft -verbatim try %{
      execute-keys 's\B#([0-9A-Fa-f]{6})\b<ret>'
      evaluate-commands -itersel %{
        set-option -add window colorize_ranges "%val{selection_desc}|default,rgb:%reg{1}"
      }
    }

    # Hex 3-digit: #RGB
    evaluate-commands -draft -verbatim try %{
      execute-keys 's\B#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])\b<ret>'
      evaluate-commands -itersel %{
        set-option -add window colorize_ranges "%val{selection_desc}|default,rgb:%reg{1}%reg{1}%reg{2}%reg{2}%reg{3}%reg{3}"
      }
    }

    # Kakoune face format: rgb:RRGGBB
    evaluate-commands -draft -verbatim try %{
      execute-keys 'srgb:([0-9A-Fa-f]{6})\b<ret>'
      evaluate-commands -itersel %{
        set-option -add window colorize_ranges "%val{selection_desc}|default,rgb:%reg{1}"
      }
    }

    # CSS rgb()/rgba() — pure shell, no python
    evaluate-commands -draft -verbatim try %{
      execute-keys 'srgba?\([^)]+\)<ret>'
      evaluate-commands -itersel %{
        evaluate-commands %sh{
          hex=$(echo "$kak_selection" | awk '{gsub(/[^0-9. ]+/," "); printf "%02x%02x%02x",int($1),int($2),int($3)}')
          [ -n "$hex" ] && printf 'set-option -add window colorize_ranges "%%val{selection_desc}|default,rgb:%s"\n' "$hex"
        }
      }
    }

    # CSS hsl()/hsla()
    evaluate-commands -draft -verbatim try %{
      execute-keys 'shsla?\([^)]+\)<ret>'
      evaluate-commands -itersel %{
        evaluate-commands %sh{
          hex=$(python3 << 'PY'
import colorsys, re, os
m = re.match(r'hsla?\(([^)]+)\)', os.environ['kak_selection'])
if m:
    p = [x.strip().rstrip('%') for x in re.split(r'[,\s]+', m.group(1).strip())[:3]]
    r,g,b = colorsys.hls_to_rgb(float(p[0])/360, float(p[2])/100, float(p[1])/100)
    print(f'{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}')
PY
)
          [ -n "$hex" ] && printf 'set-option -add window colorize_ranges "%%val{selection_desc}|default,rgb:%s"\n' "$hex"
        }
      }
    }

    # CSS oklch()
    evaluate-commands -draft -verbatim try %{
      execute-keys 'soklch\([^)]+\)<ret>'
      evaluate-commands -itersel %{
        evaluate-commands %sh{
          hex=$(python3 << 'PY'
import math, re, os
m = re.match(r'oklch\(([^)]+)\)', os.environ['kak_selection'])
if m:
    p = [float(x.strip().rstrip('%')) for x in re.split(r'[,\s]+', m.group(1).strip())[:3]]
    hr = math.radians(p[2])
    a, b = p[1]*math.cos(hr), p[1]*math.sin(hr)
    l_ = (p[0]+0.3963377774*a+0.2158037573*b)**3
    m_ = (p[0]-0.1055613458*a-0.0638541728*b)**3
    s_ = (p[0]-0.0894841775*a-1.2914855480*b)**3
    r = 4.0767416621*l_-3.3077115913*m_+0.2309699292*s_
    g = -1.2684380046*l_+2.6097574011*m_-0.3413193965*s_
    bl = -0.0041960863*l_-0.7034186147*m_+1.7076147010*s_
    ri,gi,bi = [max(0,min(255,int(v*255))) for v in (r,g,bl)]
    print(f'{ri:02x}{gi:02x}{bi:02x}')
PY
)
          [ -n "$hex" ] && printf 'set-option -add window colorize_ranges "%%val{selection_desc}|default,rgb:%s"\n' "$hex"
        }
      }
    }
  }
}
