// Gradient-or-solid border tokens. One token carries either a single color
// ("#7aa2f7") or a gradient ("#26a269ee #2ec27eee 45deg") — omarchy's grammar
// for hyprland_active_border, which is where the ported values come from
// (CREDITS.md). Colors are #rgb / #rrggbb / #rrggbbaa or Hyprland's
// rgb()/rgba() spellings; the angle is the one token ending in "deg" and may
// appear anywhere in the list.
//
// Angle convention is Hyprland's, so the theme values transfer verbatim:
// 0 is left-to-right and it increases clockwise on screen (i.e. direction
// (cos a, sin a) with y growing downward). CSS — which is what niri speaks —
// measures from bottom-to-top instead, so the niri emitter adds 90.
//
// Plain JS with no QML dependencies, so both Services/Theme.qml (via import)
// and bin/theme-apply (via eval) share one parser, the same way color.js is
// shared.

function _pad(n) {
  var v = Math.max(0, Math.min(255, Math.round(Number(n) || 0)))
  var s = v.toString(16)
  return s.length < 2 ? "0" + s : s
}

// Canonicalize one color token to #rrggbb or #rrggbbaa. Returns "" for
// anything unrecognized, so callers can tell a color from an angle or noise.
function canonicalColor(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  var m

  m = s.match(/^#([0-9A-Fa-f]{3})$/)
  if (m) {
    var h = m[1]
    return "#" + h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  }

  m = s.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/)
  if (m) return "#" + m[1].toLowerCase() + (m[2] ? m[2].toLowerCase() : "")

  m = s.match(/^[Rr][Gg][Bb][Aa]?\(([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?\)$/)
  if (m) return "#" + m[1].toLowerCase() + (m[2] ? m[2].toLowerCase() : "")

  m = s.match(/^[Rr][Gg][Bb]\(([0-9]+),\s*([0-9]+),\s*([0-9]+)\)$/)
  if (m) return "#" + _pad(m[1]) + _pad(m[2]) + _pad(m[3])

  m = s.match(/^[Rr][Gg][Bb][Aa]\(([0-9]+),\s*([0-9]+),\s*([0-9]+),\s*([0-9.]+)\)$/)
  if (m) return "#" + _pad(m[1]) + _pad(m[2]) + _pad(m[3]) + _pad(Number(m[4]) * 255)

  return ""
}

// { colors: ["#rrggbb", ...], angle: <deg>, enabled: colors.length > 1 }
function parseSpec(spec) {
  var parts = String(spec === undefined || spec === null ? "" : spec).trim().split(/\s+/)
  var colors = []
  var angle = 0
  for (var i = 0; i < parts.length; i++) {
    if (!parts[i]) continue
    var deg = parts[i].match(/^(-?\d+(?:\.\d+)?)deg$/)
    if (deg) {
      angle = Number(deg[1])
      continue
    }
    var c = canonicalColor(parts[i])
    if (c) colors.push(c)
  }
  return { colors: colors, angle: isFinite(angle) ? angle : 0, enabled: colors.length > 1 }
}

// The flat color a gradient token degrades to for color-only consumers:
// its first stop (omarchy's gradient_start / firstColorToken).
function firstColor(spec) {
  var g = parseSpec(spec)
  return g.colors.length > 0 ? g.colors[0] : ""
}

function isGradient(spec) {
  return parseSpec(spec).enabled
}

// Endpoints of the gradient line across a w×h box, verbatim from omarchy's
// BorderGeometry.gradientEndpoints: the line runs through the centre along
// the angle, long enough to cover the box's projection onto it.
function endpoints(w, h, angle) {
  w = Math.max(1, Number(w) || 1)
  h = Math.max(1, Number(h) || 1)
  var rad = (Number(angle) || 0) * Math.PI / 180
  var dx = Math.cos(rad)
  var dy = Math.sin(rad)
  var len = (Math.abs(w * dx) + Math.abs(h * dy)) / 2
  return { x1: w / 2 - dx * len, y1: h / 2 - dy * len, x2: w / 2 + dx * len, y2: h / 2 + dy * len }
}

// Themes (and niri, and CSS) write 8-digit hex as #rrggbbaa. Qt reads it as
// #aarrggbb, so an omarchy border value like "#26a269ee" arrives in QML as a
// 15%-opacity purple. Every color token crossing into QML goes through here;
// 6-digit values and anything unrecognized pass through untouched.
function qmlColor(hex) {
  var m = String(hex === undefined || hex === null ? "" : hex).match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})$/)
  return m ? "#" + m[2] + m[1] : hex
}

// Evenly spaced stop positions, theirs.
function stopPosition(count, index) {
  if (count <= 1) return index === 0 ? 0 : 1
  return index / (count - 1)
}

// Hyprland degrees → CSS degrees, which is what niri's `angle=` takes
// ("rendered the same as CSS linear-gradient", niri wiki).
function cssAngle(angle) {
  var a = (Number(angle) || 0) + 90
  a = a % 360
  return a < 0 ? a + 360 : a
}
