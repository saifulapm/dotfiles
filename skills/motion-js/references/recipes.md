# Motion.js Animation Recipes

Copy-paste-ready patterns for common animations in the Nova theme. All imports use the `'vendor'` bare specifier — make sure each function is exported from `src/vendor.ts` first.

## Table of Contents

1. [Scroll: Fade In/Out](#scroll-fade-inout)
2. [Scroll: Horizontal Pinning Gallery](#scroll-horizontal-pinning-gallery)
3. [Scroll: Triggered Entrance](#scroll-triggered-entrance)
4. [Scroll: Progress Bar](#scroll-progress-bar)
5. [Parallax](#parallax)
6. [Stagger List Items](#stagger-list-items)
7. [Hover Effect](#hover-effect)
8. [Press / Button Feedback](#press-button-feedback)
9. [Combined Gesture State](#combined-gesture-state)
10. [Loading: Circle Spinner](#loading-circle-spinner)
11. [Loading: Jumping Dots](#loading-jumping-dots)
12. [Loading: Pulse Dots](#loading-pulse-dots)
13. [Loading: SVG Spinner](#loading-svg-spinner)
14. [Counter / Number Animation](#counter-number-animation)
15. [Color Interpolation](#color-interpolation)
16. [Bounce Easing (Custom)](#bounce-easing-custom)
17. [SVG Path Drawing](#svg-path-drawing)
18. [SVG Path Morphing (with Flubber)](#svg-path-morphing)
19. [Characters Remaining Indicator](#characters-remaining-indicator)
20. [Spring Animation](#spring-animation)
21. [Infinite Rotation](#infinite-rotation)

---

## Scroll: Fade In/Out

Elements fade in as they enter the viewport and fade out as they leave.

```typescript
import { animate, scroll } from 'vendor'

document.querySelectorAll(".fade-section > div").forEach((item) => {
  scroll(
    animate(item, { opacity: [0, 1, 1, 0] }),
    {
      target: item,
      offset: ["start end", "end end", "start start", "end start"]
    }
  )
})
```

**CSS:** Sections should be `height: 100vh`. No initial opacity needed — scroll controls it.

---

## Scroll: Horizontal Pinning Gallery

Vertical scroll drives horizontal movement of pinned content.

```html
<section class="gallery-container" style="height: 500vh; position: relative;">
  <div style="position: sticky; top: 0; overflow: hidden; height: 100vh;">
    <div class="gallery-track" style="display: flex;">
      <!-- Items, each 100vw wide -->
    </div>
  </div>
</section>
```

```typescript
import { animate, scroll } from 'vendor'

const items = document.querySelectorAll(".gallery-track > *")
scroll(
  animate(".gallery-track", {
    transform: ["none", `translateX(-${items.length - 1}00vw)`]
  }),
  { target: document.querySelector(".gallery-container") }
)
```

**Key:** Container height = `${numItems}00vh`. CSS `position: sticky` does the pinning.

---

## Scroll: Triggered Entrance

Elements animate in when they enter the viewport.

```typescript
import { animate, inView } from 'vendor'

inView(".reveal", (element) => {
  animate(element, { opacity: 1, y: [30, 0] }, {
    duration: 0.6,
    ease: [0.17, 0.55, 0.55, 1]
  })
  return () => animate(element, { opacity: 0 })
})
```

**CSS:** Set initial state: `opacity: 0` on `.reveal` elements.

---

## Scroll: Progress Bar

A bar that fills as the page is scrolled.

```html
<div class="scroll-progress" style="position: fixed; top: 0; left: 0; right: 0; height: 3px; background: var(--accent); transform-origin: left; transform: scaleX(0);"></div>
```

```typescript
import { animate, scroll } from 'vendor'

scroll(animate(".scroll-progress", { scaleX: [0, 1] }, { ease: "linear" }))
```

---

## Parallax

Elements move at different speeds relative to scroll.

```typescript
import { animate, scroll } from 'vendor'

document.querySelectorAll("[data-parallax]").forEach((el) => {
  const speed = parseFloat(el.dataset.parallax) || 0.5
  scroll(
    animate(el, { y: [speed * -100, speed * 100] }, { ease: "linear" }),
    { target: el }
  )
})
```

**Usage in Liquid:**
```html
<h2 data-parallax="0.3">Slow parallax</h2>
<img data-parallax="0.8" src="..." />
```

---

## Stagger List Items

Cascade animation across multiple elements.

```typescript
import { animate, stagger } from 'vendor'

animate(".product-grid .product-card", {
  opacity: [0, 1],
  y: [40, 0]
}, {
  delay: stagger(0.08),
  duration: 0.5,
  ease: [0.17, 0.55, 0.55, 1]
})
```

**Variations:**
```typescript
// From center (ripple effect)
stagger(0.06, { from: "center" })

// From last (reverse cascade)
stagger(0.05, { from: "last" })

// With eased distribution
stagger(0.1, { ease: "easeOut" })
```

---

## Hover Effect

Scale up on hover with touch filtering.

```typescript
import { animate, hover } from 'vendor'

hover(".product-card", (element) => {
  animate(element, { scale: 1.03 }, { type: "spring", stiffness: 400, damping: 25 })
  return () => animate(element, { scale: 1 }, { type: "spring", stiffness: 300 })
})
```

---

## Press / Button Feedback

Tactile press-down effect with spring physics.

```typescript
import { animate, press } from 'vendor'

press(".btn", (element) => {
  animate(element, { scale: 0.95 }, { type: "spring", stiffness: 800, damping: 30 })
  return () => animate(element, { scale: 1 }, { type: "spring", stiffness: 400 })
})
```

---

## Combined Gesture State

Managing hover + press together without conflicts.

```typescript
import { animate, hover, press } from 'vendor'

const gestureState = new WeakMap()
const transition = { type: "spring" as const, stiffness: 500, damping: 25 }

function updateGesture(element: Element, update: Partial<{ hovered: boolean; pressed: boolean }>) {
  const state = { ...(gestureState.get(element) || { hovered: false, pressed: false }), ...update }
  gestureState.set(element, state)
  const scale = state.pressed ? 0.9 : state.hovered ? 1.08 : 1
  animate(element, { scale }, transition)
}

hover(".interactive", (el) => {
  updateGesture(el, { hovered: true })
  return () => updateGesture(el, { hovered: false })
})

press(".interactive", (el) => {
  updateGesture(el, { pressed: true })
  return () => updateGesture(el, { pressed: false })
})
```

---

## Loading: Circle Spinner

```html
<div class="spinner" style="width: 40px; height: 40px; border: 3px solid rgba(0,0,0,0.1); border-top-color: currentColor; border-radius: 50%;"></div>
```

```typescript
import { animate } from 'vendor'

animate(".spinner", { transform: "rotate(360deg)" }, {
  duration: 1,
  repeat: Infinity,
  ease: "linear"
})
```

---

## Loading: Jumping Dots

```html
<div class="loading-dots" style="display: flex; gap: 6px;">
  <div class="dot" style="width: 10px; height: 10px; border-radius: 50%; background: currentColor;"></div>
  <div class="dot" style="width: 10px; height: 10px; border-radius: 50%; background: currentColor;"></div>
  <div class="dot" style="width: 10px; height: 10px; border-radius: 50%; background: currentColor;"></div>
</div>
```

```typescript
import { animate, stagger } from 'vendor'

animate(".loading-dots .dot", { y: [-15, 0] }, {
  duration: 0.5,
  repeat: Infinity,
  repeatType: "mirror",
  ease: "easeInOut",
  delay: stagger(0.15, { startDelay: -0.4 })
})
```

---

## Loading: Pulse Dots

```typescript
import { animate, stagger } from 'vendor'

animate(".pulse-dots .dot", { scale: [1, 1.5, 1] }, {
  duration: 1.2,
  repeat: Infinity,
  delay: stagger(0.2),
  ease: "easeInOut"
})
```

---

## Loading: SVG Spinner

8-segment spinner with staggered opacity wave.

```html
<svg width="40" height="40" viewBox="0 0 200 200">
  <g class="spinner-seg" opacity="0">
    <path id="seg" d="M94 25C94 21.7 96.7 19 100 19s6 2.7 6 6v25c0 3.3-2.7 6-6 6s-6-2.7-6-6V25z"/>
  </g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(45deg)"/></g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(90deg)"/></g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(135deg)"/></g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(180deg)"/></g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(225deg)"/></g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(270deg)"/></g>
  <g class="spinner-seg" opacity="0"><use href="#seg" style="transform:rotate(315deg)"/></g>
</svg>
```

```css
.spinner-seg use, .spinner-seg path { fill: currentColor; transform-origin: 100px 100px; }
```

```typescript
import { animate, stagger } from 'vendor'

const segments = document.querySelectorAll(".spinner-seg")
const count = segments.length
const offset = 0.09
const duration = count * offset

animate(segments, { opacity: [0, 1, 0] }, {
  offset: [0, 0.1, 1],
  duration,
  delay: stagger(offset, { startDelay: -duration }),
  repeat: Infinity,
})
```

---

## Counter / Number Animation

Animate a number counting up (e.g., stats, prices).

```typescript
import { animate } from 'vendor'

const counter = document.getElementById("stat-count")
animate(0, 1250, {
  duration: 2,
  ease: "circOut",
  onUpdate: (v) => { counter.textContent = Math.round(v).toLocaleString() }
})
```

---

## Color Interpolation

Motion uses linear RGB — no sRGB dimming between colors.

```typescript
import { animate } from 'vendor'

animate(".gradient-box", {
  backgroundColor: ["#ff0088", "#1e75f7"]
}, {
  duration: 2,
  repeat: Infinity,
  repeatType: "reverse",
  ease: "linear"
})
```

---

## Bounce Easing (Custom)

Custom bounce easing function from easings.net.

```typescript
function bounceEase(x: number): number {
  const n1 = 7.5625, d1 = 2.75
  if (x < 1 / d1) return n1 * x * x
  if (x < 2 / d1) return n1 * (x -= 1.5 / d1) * x + 0.75
  if (x < 2.5 / d1) return n1 * (x -= 2.25 / d1) * x + 0.9375
  return n1 * (x -= 2.625 / d1) * x + 0.984375
}

// Use: gravity-like fall with bounce
animate(el, { y: 200 }, { duration: 1, ease: bounceEase })

// Pair with spring for asymmetric motion
animate(el, { y: isDown ? 200 : 0 }, isDown
  ? { duration: 1, ease: bounceEase }
  : { type: "spring", stiffness: 600, damping: 25 }
)
```

---

## SVG Path Drawing

Animate SVG stroke drawing.

```typescript
import { animate } from 'vendor'

// Draw in
animate("path.draw", { pathLength: [0, 1] }, { duration: 2, ease: "easeInOut" })

// Continuous drawing loop
animate("circle.loader", { pathOffset: [0, 1] }, {
  repeat: Infinity,
  ease: "linear",
  duration: 1.5
})
```

**CSS prerequisite:**
```css
path.draw { fill: none; stroke: currentColor; stroke-width: 2; }
```

---

## SVG Path Morphing

Morph between two SVG paths using Flubber library.

```typescript
import { animate } from 'vendor'
// Note: flubber must be loaded separately (not in vendor)

const paths = {
  star: "M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z",
  heart: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"
}

function morphPath(pathEl: SVGPathElement, fromD: string, toD: string, duration = 0.5) {
  const { interpolate } = await import("flubber")
  const mixer = interpolate(fromD, toD, { maxSegmentLength: 0.1 })
  animate(0, 1, {
    duration,
    onUpdate: (p) => pathEl.setAttribute("d", mixer(p))
  })
}
```

---

## Characters Remaining Indicator

Spring-animated counter that changes color as limit approaches.

```typescript
import { animate, transform } from 'vendor'

const maxLength = 140
const input = document.getElementById("message-input") as HTMLInputElement
const counter = document.getElementById("char-count")

const mapColor = transform([10, 40], ["#ff008c", "#999"])
const mapVelocity = transform([0, 20], [50, 0])

input.addEventListener("input", () => {
  const remaining = maxLength - input.value.length
  counter.textContent = String(remaining)
  counter.style.color = mapColor(remaining) as string

  if (remaining <= 40) {
    animate("#char-count", { scale: 1 }, {
      type: "spring",
      velocity: mapVelocity(remaining) as number,
      stiffness: 700,
      damping: 80
    })
  }
})
```

---

## Spring Animation

Physics-based spring for natural motion.

```typescript
import { animate } from 'vendor'

// Duration/bounce model (simpler to reason about)
animate(el, { y: 0 }, { type: "spring", duration: 0.8, bounce: 0.3 })

// Physics model (more control)
animate(el, { rotate: 90 }, { type: "spring", stiffness: 300, damping: 20, mass: 1 })

// Looping spring
animate(el, { scale: [0.8, 1.2] }, {
  type: "spring",
  repeat: Infinity,
  repeatType: "mirror",
  repeatDelay: 0.1
})
```

**Quick spring presets:**
```typescript
const springs = {
  snappy:  { type: "spring" as const, stiffness: 500, damping: 30 },
  bouncy:  { type: "spring" as const, stiffness: 300, damping: 15 },
  gentle:  { type: "spring" as const, stiffness: 150, damping: 20 },
  stiff:   { type: "spring" as const, stiffness: 800, damping: 35 },
}
```

---

## Infinite Rotation

```typescript
import { animate } from 'vendor'

animate(".icon-spin", { rotate: 360 }, {
  duration: 2,
  repeat: Infinity,
  ease: "linear"
})
```
