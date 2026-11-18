// Pure pieces of the region picker; a region is {x, y, w, h} in the output's logical pixels.
export const STEP = 20;
export const MIN = 16;
// How far from a corner a press still takes its handle, a 14 px circle, in px.
const REACH = 10;

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

// One axis of a drag held at a and pulled to p: at least MIN long, growing away from a, inside 0..size.
function axis(a, p, size) {
  const q = clamp(Math.round(p), 0, size);
  const len = Math.min(size, Math.max(MIN, Math.abs(q - a)));
  return [clamp(q < a ? a - len : a, 0, size - len), len];
}

// The region a drag draws from the held point a to the pointer p, both {x, y}.
export function span(a, p, out) {
  const [x, w] = axis(Math.round(a.x), p.x, out.width);
  const [y, h] = axis(Math.round(a.y), p.y, out.height);
  return { x, y, w, h };
}

// The corner opposite the handle a press at x, y takes, which the drag then holds; null when the press is on no handle.
export function grab(r, x, y) {
  for (const cx of [0, 1]) {
    for (const cy of [0, 1]) {
      if (Math.abs(x - (r.x + cx * r.w)) <= REACH && Math.abs(y - (r.y + cy * r.h)) <= REACH) return { x: r.x + (1 - cx) * r.w, y: r.y + (1 - cy) * r.h };
    }
  }
  return null;
}

export function start(out) {
  const w = Math.round(out.width / 2), h = Math.round(out.height / 2);
  return { x: Math.round((out.width - w) / 2), y: Math.round((out.height - h) / 2), w, h };
}

export function move(r, dx, dy, out) {
  return { x: clamp(r.x + dx * STEP, 0, out.width - r.w), y: clamp(r.y + dy * STEP, 0, out.height - r.h), w: r.w, h: r.h };
}

export function resize(r, dw, dh, out) {
  return { x: r.x, y: r.y, w: clamp(r.w + dw * STEP, MIN, out.width - r.x), h: clamp(r.h + dh * STEP, MIN, out.height - r.y) };
}

export function full(out) {
  return { x: 0, y: 0, w: out.width, h: out.height };
}

export function geometry(r, out) {
  return `${out.x + r.x},${out.y + r.y} ${r.w}x${r.h}`;
}

const pad = (n) => String(n).padStart(2, '0');

export function fileName(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}.mp4`;
}
