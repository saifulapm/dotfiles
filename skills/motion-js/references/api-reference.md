# Motion.js API Reference

Complete API documentation for all Motion.js functions.

## Table of Contents

1. [animate](#animate)
2. [scroll](#scroll)
3. [hover](#hover)
4. [press](#press)
5. [inView](#inview)
6. [resize](#resize)
7. [stagger](#stagger)
8. [spring](#spring)
9. [motionValue](#motionvalue)
10. [mapValue](#mapvalue)
11. [transformValue](#transformvalue)
12. [springValue](#springvalue)
13. [styleEffect](#styleeffect)
14. [attrEffect](#attreffect)
15. [svgEffect](#svgeffect)
16. [propEffect](#propeffect)
17. [transform](#transform)
18. [mix](#mix)
19. [wrap](#wrap)
20. [delay](#delay)
21. [frame](#frame)
22. [Easing Functions](#easing-functions)
23. [CSS Spring Generation](#css-spring-generation)

---

## animate

Two versions: **mini** (2.3kb, `motion/mini`) and **hybrid** (18kb, `motion`).

### Signatures

```typescript
// HTML/SVG elements
animate(target: string | Element | Element[] | NodeList, keyframes: object, options?: object): AnimationControls

// Single values (hybrid only)
animate(from: number | string, to: number | string, options?: object): AnimationControls

// Motion values (hybrid only)
animate(value: MotionValue, target: number | string, options?: object): AnimationControls

// Objects (hybrid only)
animate(target: object, keyframes: object, options?: object): AnimationControls

// Timeline sequences (hybrid only)
animate(sequence: SequenceSegment[], options?: object): AnimationControls
```

### Target types

- **CSS selector**: `"div"`, `".class"`, `"#id"`, `"ul > li"`
- **Element**: `document.getElementById("box")`
- **NodeList**: `document.querySelectorAll(".item")`
- **Element array**: `[el1, el2, el3]`

### Keyframes

```typescript
// Single target value (animates from current)
{ opacity: 1, x: 100 }

// Explicit keyframes array
{ opacity: [0, 1], y: [50, 0] }

// Multi-step keyframes
{ opacity: [0, 1, 1, 0], scale: [0.8, 1, 1, 0.8] }
```

### Animatable properties

**CSS properties:** opacity, backgroundColor, color, width, height, borderRadius, boxShadow, filter, etc.

**Independent transforms (hybrid only):** x, y, z, scale, scaleX, scaleY, rotate, rotateX, rotateY, rotateZ, skewX, skewY, transformPerspective

**CSS variables (hybrid only):** `"--rotate"`, `"--color"`, etc. (must be registered in modern browsers for mini)

**SVG path properties (hybrid only):** pathLength (0-1), pathSpacing (0-1), pathOffset (0-1)

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `duration` | 0.3 (0.8 multi-kf) | Duration in seconds |
| `delay` | 0 | Delay in seconds. Negative starts mid-animation |
| `ease` | `"easeOut"` | Easing function (see Easing section) |
| `times` | auto | Array of 0-1 values positioning keyframes |
| `type` | `"tween"` | `"tween"`, `"spring"`, or `"inertia"` (hybrid) |
| `repeat` | 0 | Number of repeats, or `Infinity` |
| `repeatType` | `"loop"` | `"loop"`, `"reverse"`, `"mirror"` |
| `repeatDelay` | 0 | Seconds between repetitions |
| `onUpdate` | — | Callback with latest value (single-value only) |

**Spring options** (override duration when set):

| Option | Default | Description |
|--------|---------|-------------|
| `bounce` | 0.25 | 0 (no bounce) to 1 (extreme). Simpler model |
| `visualDuration` | — | Overrides duration. Seconds to visually reach target |
| `stiffness` | 1 | Higher = more sudden |
| `damping` | 10 | Opposing force. 0 = infinite oscillation |
| `mass` | 1 | Higher = more lethargic |
| `velocity` | current | Initial spring velocity |
| `restSpeed` | 0.1 | End threshold for speed |
| `restDelta` | 0.01 | End threshold for distance |

**Per-value overrides:**
```typescript
animate(el, { x: 100, rotate: 360 }, {
  duration: 1,
  x: { type: "spring", stiffness: 300 },
  rotate: { duration: 2, ease: "linear" }
})
```

### Controls (return value)

| Property/Method | Description |
|----------------|-------------|
| `.duration` | Read-only duration of single iteration |
| `.time` | Get/set current time in seconds |
| `.speed` | Get/set playback speed (1=normal, -1=reverse) |
| `.pause()` | Pause animation |
| `.play()` | Play/resume. If finished, restarts |
| `.stop()` | Stop and commit current state. Cannot restart |
| `.complete()` | Jump to end state |
| `.cancel()` | Cancel and revert to initial state |
| `.then()` | Promise-based, resolves on finish |

### Timeline Sequences

```typescript
type SequenceSegment = [
  target: string | Element | Element[] | MotionValue,
  keyframes: object | string | number,
  options?: object & { at?: At }
]

type At = number | string | "<" | `+${number}` | `-${number}` | `<${number}`
```

**`at` scheduling:**

| Value | Meaning |
|-------|---------|
| `1.5` | At 1.5 seconds |
| `"my-label"` | At named label |
| `"<"` | Start of previous segment |
| `"+0.5"` | 0.5s after end of previous |
| `"-0.2"` | 0.2s before end of previous |
| `"<0.5"` | 0.5s after start of previous |

**Callbacks in sequences:**
```typescript
const sequence = [
  [(progress) => console.log(progress)]  // fires with 0-1 progress
]
```

**Sequence-level options:**
```typescript
animate(sequence, {
  duration: 10,           // override total duration
  repeat: 2,
  defaultTransition: { duration: 0.2 }  // default for all segments
})
```

---

## scroll

Links animations or callbacks to scroll progress. Uses ScrollTimeline API for hardware acceleration where available.

```typescript
scroll(target: AnimationControls | ((progress: number, info: ScrollInfo) => void), options?: ScrollOptions): () => void
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `container` | `window` | Scrollable element to track |
| `axis` | `"y"` | `"x"` or `"y"` |
| `target` | — | Element to track within viewport |
| `offset` | `["start start", "end end"]` | Intersection offset pairs |
| `trackContentSize` | `false` | Auto-track content size changes |

### ScrollInfo object

```typescript
info.time               // timestamp
info.x.current          // current scroll position
info.x.offset           // scroll offsets as pixels
info.x.progress         // 0-1 progress
info.x.scrollLength     // total scrollable length
info.x.velocity          // scroll velocity
info.y                  // same structure for y axis
```

### Offset format

Each offset is `"targetEdge containerEdge"`:
- Names: `"start"` (0), `"center"` (0.5), `"end"` (1)
- Numbers: `0`, `0.5`, `1` (can exceed range)
- Pixels: `"100px"`, `"-50px"`
- Percent: `"0%"` to `"100%"`
- Viewport: `"50vh"`, `"100vw"`

Returns a cancel function.

---

## hover

Detects hover gestures, filtering touch-emulated events that cause stuck hover states.

```typescript
hover(target: string | Element | Element[], callback: (element: Element, startEvent: PointerEvent) => void | (() => void), options?: { passive?: boolean, once?: boolean }): () => void
```

- Callback receives `(element, startEvent)`
- Return a function for hover-end behavior
- Returns a cancel function

---

## press

Detects press gestures. Filters secondary pointer events, adds keyboard accessibility.

```typescript
press(target: string | Element | Element[], callback: (element: Element, startEvent: PointerEvent) => void | ((endEvent: PointerEvent, info: { success: boolean }) => void), options?: { passive?: boolean, once?: boolean }): () => void
```

- `info.success` is `true` if press completed on the element (like a click)
- `info.success` is `false` if pointer left element before release
- Keyboard: fires on focus + enter key

---

## inView

Detects elements entering/leaving viewport. Built on Intersection Observer (off main thread).

```typescript
inView(target: string | Element | Element[], callback: (element: Element, info: IntersectionObserverEntry) => void | (() => void), options?: InViewOptions): () => void
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `root` | `window` | Root element for detection |
| `margin` | `"0px"` | Expand/contract viewport (up to 4 values) |
| `amount` | `"some"` | `"some"`, `"all"`, or number 0-1 |

- Returns cleanup from callback to detect leave (and re-detect enter)
- Without return function, fires once per element

---

## resize

Monitors size changes. All handlers share a single ResizeObserver.

```typescript
// Viewport
resize(callback: (info: { width: number, height: number }) => void): () => void

// Elements
resize(target: string | Element | Element[], callback: (element: Element, info: { width: number, height: number }) => void): () => void
```

---

## stagger

Creates incremental delays for multi-element animations.

```typescript
stagger(duration: number, options?: StaggerOptions): (index: number, total: number) => number
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `startDelay` | 0 | Initial delay offset |
| `from` | `"first"` | `"first"`, `"center"`, `"last"`, or index number |
| `ease` | `"linear"` | Easing for delay distribution |

---

## spring

Creates spring generators or CSS spring transitions.

### As generator (advanced)
```typescript
const gen = spring({ keyframes: [0, 100], stiffness: 400 })
const { value, done } = gen.next(timeInMs)
```

### As CSS transition
```typescript
element.style.transition = "all " + spring(visualDuration?, bounce?)
// spring(0.5, 0.2) → "800ms linear(...)"
```

### Options

Same spring physics options as animate: `duration` (ms when used directly), `visualDuration`, `bounce`, `stiffness`, `damping`, `mass`, `velocity`, `restSpeed`, `restDelta`, `keyframes`.

---

## motionValue

Reactive, composable animation values with velocity tracking.

```typescript
const x = motionValue(initialValue: number | string): MotionValue
```

### Methods

| Method | Description |
|--------|-------------|
| `.get()` | Returns current state |
| `.set(value)` | Sets new state |
| `.jump(value)` | Sets state, resets velocity to 0, ends animations |
| `.getVelocity()` | Returns current velocity (0 for non-numerical) |
| `.isAnimating()` | Returns true if currently animating |
| `.stop()` | Stops active animation |
| `.on(event, callback)` | Subscribe. Returns unsubscribe function |
| `.destroy()` | Cleanup all subscribers |

### Events

`"change"`, `"animationStart"`, `"animationCancel"`, `"animationComplete"`

```typescript
const unsub = x.on("change", (latest) => console.log(latest))
```

---

## mapValue

Creates a derived read-only motion value mapped between ranges.

```typescript
mapValue(source: MotionValue<number>, inputRange: number[], outputRange: (number | string)[], options?: { clamp?: boolean }): MotionValue
```

- Input range must be linear (counting up or down)
- Output can be numbers, colors, or complex strings
- Clamped by default; pass `{ clamp: false }` to unclamp

---

## transformValue

Creates a computed read-only motion value from other motion values.

```typescript
transformValue(compute: () => T): MotionValue<T>
```

Auto-tracks any `.get()` calls inside the compute function.

```typescript
const filter = transformValue(() => `blur(${blur.get()}px)`)
```

---

## springValue

Creates a motion value that reacts to changes with spring physics.

```typescript
springValue(initial: number | string, options?: SpringOptions): MotionValue
springValue(source: MotionValue, options?: SpringOptions): MotionValue
```

When attached to another motion value, any `.set()` on the source triggers a spring animation.

---

## styleEffect

Binds motion values to element `.style` properties. Renders once per frame.

```typescript
styleEffect(target: string | Element | Element[], values: Record<string, MotionValue>): () => void
```

Supports independent transforms (`x`, `scaleY`), default unit types, CSS properties. Returns cancel function.

---

## attrEffect

Binds motion values to element attributes. Auto-converts camelCase to kebab-case for aria/data attrs.

```typescript
attrEffect(target: string | Element | Element[], values: Record<string, MotionValue>): () => void
```

---

## svgEffect

Binds motion values to SVG element styles and attributes.

```typescript
svgEffect(target: string | Element | Element[], values: Record<string, MotionValue>): () => void
```

**Special SVG values:** `pathLength` (0-1), `pathSpacing` (0-1), `pathOffset` (0-1)

**Prefix `attr` for name conflicts:** `{ attrWidth: value }` sets the `width` attribute instead of style.

Auto-applies `transform-box: fill-box` for CSS-like transform origins on SVG elements.

Supported draw elements: `<circle>`, `<ellipse>`, `<line>`, `<path>`, `<polygon>`, `<polyline>`, `<rect>`

---

## propEffect

Binds motion values to object properties (e.g., Three.js).

```typescript
propEffect(target: object, values: Record<string, MotionValue>): () => void
```

---

## transform

Maps input values from one range to another.

```typescript
transform(inputRange: number[], outputRange: (number | string)[], options?: { clamp?: boolean }): (value: number) => number | string
```

- Both ranges must be same length
- Input range must be linear
- Output can be numbers, colors, complex strings
- Clamped by default

---

## mix

Creates a mixer function between two values.

```typescript
mix(from: T, to: T): (progress: number) => T
```

Mixes: numbers, colors (linear RGB), complex strings, arrays, objects. Accepts values outside 0-1 range.

---

## wrap

Wraps a value within a range.

```typescript
wrap(min: number, max: number, value: number): number
```

```typescript
wrap(0, 10, 11) // 1
wrap(0, 10, -1) // 9
```

---

## delay

`setTimeout` alternative synced to Motion's animation frameloop.

```typescript
delay(callback: () => void, duration: number): () => void  // returns cancel
```

Duration in seconds.

---

## frame

Schedule functions on Motion's animation loop. Prevents layout thrashing.

```typescript
frame.read(callback, keepAlive?: boolean)
frame.update(callback, keepAlive?: boolean)
frame.render(callback, keepAlive?: boolean)
```

- `read`: Measure DOM
- `update`: Compute values
- `render`: Write to DOM

Pass `true` as second arg to keep firing every frame (animation loop). Cancel with `cancelFrame(callback)`.

---

## Easing Functions

### Named easings (string)
`"linear"`, `"easeIn"`, `"easeOut"`, `"easeInOut"`, `"circIn"`, `"circOut"`, `"circInOut"`, `"backIn"`, `"backOut"`, `"backInOut"`, `"anticipate"`

### Cubic bezier
```typescript
ease: [0.42, 0, 0.58, 1]
```

### Function
```typescript
ease: (progress: number) => number  // 0-1 input, eased output
```

### Importable functions
`easeIn`, `easeOut`, `easeInOut`, `circIn`, `circOut`, `circInOut`, `backIn`, `backOut`, `backInOut`, `anticipate`, `linear`

### Generators
```typescript
cubicBezier(x1, y1, x2, y2)  // returns easing function
steps(numSteps, position?)     // CSS steps() equivalent, position: "start" | "end"
```

### Modifiers
```typescript
reverseEasing(fn)  // ease-in → ease-out
mirrorEasing(fn)   // ease-in → ease-in-out
```

### Per-keyframe easing
```typescript
animate(el, { opacity: [0, 0.5, 1] }, { ease: ["easeIn", "easeOut"] })
```

---

## CSS Spring Generation

```typescript
import { spring } from "motion"

// Returns string usable in CSS transition
spring(visualDuration?: number, bounce?: number).toString()
// e.g., "800ms linear(...)"

// Direct usage
element.style.transition = `transform ${spring(0.5, 0.2)}`
```

`visualDuration` is time to first reach target (bounce happens after). Generated duration may be longer.

Fallback for browsers without `linear()`:
```css
transition: transform 0.3s ease-out;         /* fallback */
transition: transform ${spring(0.3)};        /* override */
```
