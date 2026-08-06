---
name: motion-js
description: >
  Create animations using Motion.js in the Nova Shopify theme. Use this skill whenever the user asks
  to animate anything, add motion effects, create hover/press/scroll/loading/parallax/stagger
  animations, gesture interactions, scroll-linked effects, entrance animations, SVG animations,
  spring physics, or any visual motion on the storefront. Also trigger when user mentions "animate",
  "animation", "transition", "motion", "fade in", "slide in", "bounce", "spring", "parallax",
  "scroll effect", "loading spinner", "stagger", "hover effect", "press effect", or wants to make
  any UI element move, appear, or respond to user interaction.
---

# Motion.js for Nova Theme

Motion.js is a hybrid animation engine combining browser performance (Web Animations API) with
JavaScript power. This skill covers the vanilla JS API — not React components.

## Nova Theme Import Pattern

The Nova theme uses an ES module importmap. Motion.js exports live in `src/vendor.ts` and are
bundled into `assets/vendor.min.js`. Theme code imports from the `"vendor"` bare specifier.

**Currently exported from vendor.ts:**
```typescript
export { animate, stagger, inView, scroll } from 'motion'
```

### Adding new Motion.js exports

When you need a function not yet in vendor.ts (e.g., `hover`, `press`, `motionValue`, `spring`):

1. Add the export to `src/vendor.ts`:
   ```typescript
   export { animate, stagger, inView, scroll, hover, press } from 'motion'
   ```
2. Rebuild vendor: `pnpm build:vendor`
3. Import in theme code from `'vendor'`:
   ```typescript
   import { hover, press } from 'vendor'
   ```

Always check `src/vendor.ts` before writing animation code — if a function isn't exported yet, add it first.

### Where animation code lives

- **Reusable animation modules** go in `src/components/` as TypeScript files, exported through `src/components/index.ts`
- **Section-specific scripts** can use inline `<script type="module">` in Liquid files, importing from the vendor importmap
- The theme entry point `src/theme.ts` imports all components

## Choosing the Right API

| Task | API | Size |
|------|-----|------|
| Animate HTML/SVG styles | `animate` (mini: `motion/mini`) | 2.3kb |
| Animate transforms independently, CSS vars, SVG paths, sequences, objects | `animate` (hybrid: `motion`) | 18kb |
| Scroll-linked/progress animations | `scroll` | 5.1kb |
| Detect element entering viewport | `inView` | 0.5kb |
| Hover with touch filtering | `hover` | — |
| Press with keyboard a11y | `press` | — |
| Monitor element/viewport resize | `resize` | — |
| Stagger delays across elements | `stagger` | — |
| Spring physics easing | `spring` | — |
| Reactive animated values | `motionValue`, `springValue` | — |
| Bind values to element styles | `styleEffect` | — |
| Bind values to SVG attrs | `svgEffect` | — |
| Map value ranges | `transform`, `mapValue` | — |
| Animate in CSS (server-safe) | `spring()` toString | — |
| View/page transitions | `animateView` (Motion+) | — |
| Automatic layout animation | `animateLayout` (Motion+) | — |
| Text scramble/decode effect | `scrambleText` (Motion+) | — |
| Split text for per-char/word animation | `splitText` (Motion+) | — |

## Core API Quick Reference

### animate(target, keyframes, options)

```typescript
// CSS selector
animate(".box", { opacity: [0, 1], y: [20, 0] }, { duration: 0.5 })

// DOM element
animate(element, { scale: 1.2 }, { type: "spring", stiffness: 300 })

// Multiple keyframes
animate("h1", { opacity: [0, 1, 1, 0] }, { duration: 2 })

// Value animation (for non-CSS things like counters)
animate(0, 100, { duration: 2, onUpdate: (v) => el.textContent = Math.round(v) })
```

**Key options:**
- `duration` — seconds (default: 0.3, or 0.8 for multi-keyframe)
- `delay` — seconds, negative starts mid-animation
- `ease` — `"linear"`, `"easeInOut"`, `"circOut"`, `[.17,.67,.83,.67]`, or function
- `type` — `"spring"` for physics-based
- `repeat` — number or `Infinity`
- `repeatType` — `"loop"`, `"reverse"`, `"mirror"`
- `stiffness`, `damping`, `mass` — spring physics
- `bounce` — 0-1, simpler spring control
- `onUpdate` — callback with latest value (single-value animations)

**Per-value overrides:**
```typescript
animate(el, { x: 100, rotate: 0 }, {
  duration: 1,
  rotate: { duration: 0.5, ease: "easeOut" }
})
```

**Controls (return value):**
```typescript
const anim = animate(el, { opacity: 1 })
anim.pause()
anim.play()
anim.stop()       // commits current state, can't restart
anim.complete()   // jump to end
anim.cancel()     // revert to initial state
anim.time = 0.5   // seek
anim.speed = 2    // playback speed
await anim         // promise-based completion
```

### Timeline Sequences

```typescript
const sequence = [
  [".overlay", { opacity: [0, 1] }, { duration: 0.3 }],
  [".content", { y: [20, 0], opacity: [0, 1] }, { duration: 0.4, at: "-0.1" }],
  [".title", { x: [-50, 0] }, { at: "<" }]  // starts with previous
]
animate(sequence)
```

**`at` scheduling:**
- Number: absolute seconds (`{ at: 0.5 }`)
- `"<"`: start of previous segment
- `"+0.2"` / `"-0.1"`: relative to end of previous
- `"<0.5"`: relative to start of previous

### scroll(animation | callback, options)

```typescript
// Link animation to scroll progress
scroll(animate(".progress", { scaleX: [0, 1] }, { ease: "linear" }))

// Track specific element
scroll(
  animate(el, { opacity: [0, 1, 1, 0] }),
  { target: el, offset: ["start end", "end end", "start start", "end start"] }
)

// Callback with progress 0-1
scroll((progress) => { /* ... */ })

// Horizontal scroll
scroll(callback, { axis: "x" })

// Custom scroll container
scroll(callback, { container: document.querySelector(".scroller") })
```

**Offset values:** `"start"`, `"center"`, `"end"`, pixels (`"100px"`), percent (`"50%"`), viewport units (`"50vh"`)

### stagger(duration, options)

```typescript
animate("li", { opacity: 1, y: [30, 0] }, { delay: stagger(0.08) })

// From center
stagger(0.05, { from: "center" })

// From last
stagger(0.05, { from: "last" })

// With initial delay
stagger(0.1, { startDelay: 0.2 })

// Negative start (begin mid-animation for looping)
stagger(0.09, { startDelay: -duration })

// With easing
stagger(0.1, { ease: "easeOut" })
```

### Gestures: hover(target, callback) and press(target, callback)

```typescript
// hover — automatically filters touch events
hover(".card", (element) => {
  animate(element, { scale: 1.05 })
  return () => animate(element, { scale: 1 })  // hover end
})

// press — filters right clicks, adds keyboard a11y (focus+enter)
press(".btn", (element) => {
  animate(element, { scale: 0.95 }, { type: "spring", stiffness: 800 })
  return (endEvent, info) => {
    animate(element, { scale: 1 })
    if (info.success) { /* completed press, like a click */ }
  }
})

// Combining gestures with state
const state = new WeakMap()
hover(".box", (el) => {
  state.set(el, { ...(state.get(el) || {}), hovered: true })
  animate(el, { scale: 1.1 })
  return () => {
    state.set(el, { ...(state.get(el) || {}), hovered: false })
    animate(el, { scale: 1 })
  }
})
```

### inView(target, callback, options)

```typescript
inView(".section", (element) => {
  animate(element, { opacity: 1, y: [30, 0] }, { duration: 0.6 })
  return () => animate(element, { opacity: 0 })  // leave viewport
})

// Options
inView(el, callback, {
  root: scrollContainer,     // default: window
  margin: "0px 0px -100px",  // shrink/expand detection area
  amount: "all"              // "some" (default), "all", or 0-1
})
```

### Spring Physics

```typescript
// Duration/bounce model (simpler)
animate(el, { y: 0 }, { type: "spring", bounce: 0.25, duration: 0.8 })

// Physics model (more control)
animate(el, { rotate: 90 }, { type: "spring", stiffness: 300, damping: 20, mass: 1 })

// For mini animate, import spring separately
import { spring } from 'vendor'  // add to vendor.ts first
animate(el, { transform: "translateX(100px)" }, { type: spring, stiffness: 400 })
```

### Motion Values & Effects

For reactive, composable animations — read `references/api-reference.md` for full details.

```typescript
// Create reactive values
const x = motionValue(0)
const opacity = motionValue(1)

// Bind to elements (renders once per frame)
styleEffect(".box", { x, opacity })

// Animate
animate(x, 100)
x.set(200)

// Derived values
const filter = transformValue(() => `blur(${blur.get()}px)`)

// Spring-attached values
const springX = springValue(pointerX, { stiffness: 300 })

// Map ranges
const mappedOpacity = mapValue(scrollProgress, [0, 100], [0, 1])

// SVG-specific (handles pathLength, transform-origin)
svgEffect("circle", { pathLength, cx })

// Object props (Three.js etc)
propEffect(cube.position, { x, y, z })
```

### Utility Functions

```typescript
// transform — map value ranges
const toColor = transform([0, 100], ["#ff0088", "#ccc"])
toColor(50) // interpolated color

// mix — interpolate between two values
const mixer = mix(0, 100)
mixer(0.5) // 50
// Also mixes colors in linear RGB (vibrant, no dimming)
mix("#ff0088", "#1e75f7")(0.5)

// wrap — constrain to range (great for carousels)
wrap(0, numItems, currentIndex + 1)

// delay — setTimeout alternative synced to animation frameloop
const cancel = delay(() => { /* ... */ }, 1)

// frame — schedule reads/writes to prevent layout thrashing
frame.read(() => { /* measure DOM */ })
frame.render(() => { /* write to DOM */ })
```

### SVG Path Animations

```typescript
// Draw animation (pathLength 0-1)
animate("circle", { pathLength: [0, 1] }, { duration: 2 })

// Infinite drawing loop
animate("path", { pathOffset: [0, 1] }, { repeat: Infinity, ease: "linear" })

// Supported elements: circle, ellipse, line, path, polygon, polyline, rect
```

### CSS Spring Generation (Server-safe)

```typescript
// Generate CSS transition with spring easing
element.style.transition = `transform ${spring(0.5, 0.2)}`
// Outputs: transform 800ms linear(...)
```

## Motion+ Premium APIs (requires one-time purchase)

These APIs are available if you have Motion+ installed:

- **`animateView`** — Wraps the browser's View Transition API for smooth layout-to-layout animations (e.g., tab switching, card expand/collapse, page transitions)
- **`animateLayout`** — Automatic layout animations when DOM changes
- **`scrambleText`** — Scramble/decode text animation effect
- **`splitText`** — Split text into individual characters, words, or lines for per-element animation

```typescript
// animateView example (View Transitions)
import { animateView, press } from 'vendor'

press(".tab", (element) => {
  animateView(() => {
    // Change DOM/layout here — animateView handles the transition
    updateActiveTab(element)
  })
})

// splitText example
import { splitText, animate, stagger } from 'vendor'

const { words } = splitText(".hero-title")
animate(words, { opacity: [0, 1], y: [20, 0] }, { delay: stagger(0.05) })
```

If using these, add them to `src/vendor.ts` exports and rebuild vendor.

## Common Animation Recipes

Read `references/recipes.md` for complete, copy-paste-ready animation patterns including:
- Scroll fade in/out
- Scroll pinning (horizontal gallery)
- Scroll-triggered entrance
- Parallax
- Loading spinners (circle, dots, SVG)
- Stagger list items
- Hover/press button feedback
- Counter/number animation
- Color interpolation
- Bounce easing
- SVG path morphing
- Gesture state management

## Important Notes

- Motion interpolates colors in **linear RGB** — vibrant transitions without sRGB dimming
- Hardware acceleration is automatic for opacity, filter, transform
- `animate()` automatically persists final state (no `fill: "forwards"` needed)
- `animate()` automatically interrupts existing animations on the same values
- `hover()` filters touch events that cause "stuck" hover states on mobile
- `press()` adds keyboard accessibility automatically (focus + enter)
- Springs with `damping: 0` oscillate forever — always set damping > 0
- Use `will-change: transform` CSS hint sparingly for GPU compositing
- `stop()` commits current state (can't restart); `cancel()` reverts to initial
- Duration uses **seconds** (not milliseconds like WAAPI)
- Independent transforms (`x`, `y`, `scale`, `rotate`) only work with hybrid `animate` from `"motion"`, not `"motion/mini"`
