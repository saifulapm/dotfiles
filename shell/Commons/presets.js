// Theme presets — named bundles of appearance defaults a theme opts into
// with `[meta] preset = "<name>"`. A preset sits between THEME_DEFAULTS and
// the theme file in the merge order (defaults < preset < theme < machine
// override), so every key a preset sets can still be overridden per theme or
// per machine. Consumed by Services/Theme.qml (QML import), bin/theme-apply
// and bin/theme-list (eval) — one definition, three consumers, same rule as
// defaults.js.
//
// Values use the exact shapes the limited TOML walker produces: strings,
// numbers, barewords. Curve names are resolved by theme-apply's
// niri_animations emitter: linear | standard (easeOutCubic) | signature
// (easeOutQuint) | snap (easeOutExpo) | overshoot (easeOutBack) | "a b c d"
// (raw cubic-bezier points).
var THEME_PRESETS = {
  // The baseline: no blur, no shadow, omarchy's opacity pair, reference
  // motion. Identical to the pre-preset behavior.
  flat: {},

  // Frosted: compositor blur on by default, deeper translucency so the
  // frost reads, no shadow (blur and shadow together read as smudge).
  glass: {
    "blur.enabled": "true",
    "blur.alpha": 0.75,
    "opacity.active": 0.97,
    "opacity.inactive": 0.93
  },

  // Opaque windows that separate by depth instead of frost.
  shaded: {
    "shadow.enabled": "true",
    "shadow.softness": 34,
    "shadow.spread": 4,
    "shadow.offset-y": 6,
    "opacity.active": 1.0,
    "opacity.inactive": 1.0
  },

  // Springy: underdamped compositor springs, quicker shell easing.
  playful: {
    "motion.duration": 170,
    "motion.easing": "spring",
    "motion.open-ms": 340,
    "motion.open-curve": "overshoot",
    "motion.spring-damping": 0.72,
    "motion.spring-stiffness": 850,
    "motion.workspace-stiffness": 950
  },

  // Slow fades, soft wide shadows, gentle springs.
  calm: {
    "motion.duration": 240,
    "motion.open-ms": 520,
    "motion.open-curve": "standard",
    "motion.close-ms": 240,
    "motion.close-curve": "standard",
    "motion.spring-damping": 1.0,
    "motion.spring-stiffness": 700,
    "motion.workspace-stiffness": 800,
    "shadow.enabled": "true",
    "shadow.softness": 44,
    "shadow.spread": 2
  },

  // Instant-feeling: short durations, sharp exits, stiff springs.
  snap: {
    "motion.duration": 100,
    "motion.easing": "snap",
    "motion.open-ms": 190,
    "motion.open-curve": "snap",
    "motion.close-ms": 90,
    "motion.spring-stiffness": 1400,
    "motion.workspace-stiffness": 1600
  },

  // Zero motion anywhere, hard offset shadow, full opacity — the CRT-era
  // themes (retro-82) where animation would break the fiction.
  still: {
    "motion.duration": 0,
    "shadow.enabled": "true",
    "shadow.softness": 0,
    "shadow.spread": 2,
    "shadow.offset-x": 4,
    "shadow.offset-y": 4,
    "opacity.active": 1.0,
    "opacity.inactive": 1.0
  }
}
