// Contrast-by-construction, ported from noctalia src/theme/contrast.cpp
// (MIT —): WCAG ratio as the target, OKLCH as the search
// space, chroma-only gamut mapping. Plain JS with no QML dependencies so
// the math is testable outside the shell.

function _srgbToLinear(c) {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

function _linearToSrgb(c) {
  return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055
}

function hexToRgb(hex) {
  const m = String(hex).match(/^#?([0-9A-Fa-f]{6})/)
  if (!m) return null
  const h = m[1]
  return {
    r: parseInt(h.substr(0, 2), 16) / 255,
    g: parseInt(h.substr(2, 2), 16) / 255,
    b: parseInt(h.substr(4, 2), 16) / 255
  }
}

function rgbToHex(c) {
  const b = v => {
    const n = Math.max(0, Math.min(255, Math.round(v * 255)))
    return n.toString(16).padStart(2, "0")
  }
  return "#" + b(c.r) + b(c.g) + b(c.b)
}

function _rgbToOklch(c) {
  const r = _srgbToLinear(c.r), g = _srgbToLinear(c.g), bl = _srgbToLinear(c.b)
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  const a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  const b2 = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  return { L: L, C: Math.sqrt(a * a + b2 * b2), h: Math.atan2(b2, a) }
}

function _oklchToRgbRaw(o) {
  const a = o.C * Math.cos(o.h), b2 = o.C * Math.sin(o.h)
  const l = Math.pow(o.L + 0.3963377774 * a + 0.2158037573 * b2, 3)
  const m = Math.pow(o.L - 0.1055613458 * a - 0.0638541728 * b2, 3)
  const s = Math.pow(o.L - 0.0894841775 * a - 1.2914855480 * b2, 3)
  return {
    r: _linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    g: _linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    b: _linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
  }
}

function _inGamut(c) {
  const e = 1e-4
  return c.r >= -e && c.r <= 1 + e && c.g >= -e && c.g <= 1 + e && c.b >= -e && c.b <= 1 + e
}

function _clamp01(c) {
  return {
    r: Math.max(0, Math.min(1, c.r)),
    g: Math.max(0, Math.min(1, c.g)),
    b: Math.max(0, Math.min(1, c.b))
  }
}

// Reduce chroma only (hue and lightness preserved) until inside sRGB.
function _gamutMap(o) {
  let c = _oklchToRgbRaw(o)
  if (_inGamut(c)) return _clamp01(c)
  let lo = 0, hi = o.C, best = { L: o.L, C: 0, h: o.h }
  for (let i = 0; i < 20; i++) {
    const mid = (lo + hi) / 2
    const t = { L: o.L, C: mid, h: o.h }
    if (_inGamut(_oklchToRgbRaw(t))) { best = t; lo = mid } else { hi = mid }
  }
  return _clamp01(_oklchToRgbRaw(best))
}

function _relLuminance(c) {
  return 0.2126 * _srgbToLinear(c.r) + 0.7152 * _srgbToLinear(c.g) + 0.0722 * _srgbToLinear(c.b)
}

function contrastRatio(fgHex, bgHex) {
  const f = hexToRgb(fgHex), g = hexToRgb(bgHex)
  if (!f || !g) return 0
  const lf = _relLuminance(f), lg = _relLuminance(g)
  const hi = Math.max(lf, lg), lo = Math.min(lf, lg)
  return (hi + 0.05) / (lo + 0.05)
}

function isDark(hex) {
  const c = hexToRgb(hex)
  return c ? _relLuminance(c) < 0.179 : true
}

// Returns fgHex adjusted (OKLCH lightness only, hue/chroma preserved as far
// as the gamut allows) to reach minRatio against bgHex. preferLight:
// 1 = force lighten, -1 = force darken, 0 = pick from background darkness.
function ensureContrast(fgHex, bgHex, minRatio, preferLight) {
  minRatio = minRatio || 4.5
  preferLight = preferLight || 0
  if (contrastRatio(fgHex, bgHex) >= minRatio) return fgHex
  const bg = hexToRgb(bgHex), fg = hexToRgb(fgHex)
  if (!bg || !fg) return fgHex
  const src = _rgbToOklch(fg)
  const lighten = preferLight !== 0 ? preferLight > 0 : isDark(bgHex)

  const endpoint = _gamutMap({ L: lighten ? 1 : 0, C: src.C, h: src.h })
  if (contrastRatio(rgbToHex(endpoint), bgHex) < minRatio) {
    // Even the endpoint fails: try the opposite direction, return whichever
    // scores higher — degrade gracefully rather than fail.
    const opposite = _gamutMap({ L: lighten ? 0 : 1, C: src.C, h: src.h })
    return contrastRatio(rgbToHex(opposite), bgHex) > contrastRatio(rgbToHex(endpoint), bgHex)
      ? rgbToHex(opposite) : rgbToHex(endpoint)
  }

  let lo = lighten ? src.L : 0
  let hi = lighten ? 1 : src.L
  let best = endpoint
  for (let i = 0; i < 20; i++) {
    const mid = (lo + hi) / 2
    const cand = _gamutMap({ L: mid, C: src.C, h: src.h })
    if (contrastRatio(rgbToHex(cand), bgHex) >= minRatio) {
      best = cand
      if (lighten) hi = mid; else lo = mid
    } else {
      if (lighten) lo = mid; else hi = mid
    }
  }
  return rgbToHex(best)
}
