// Pure pieces of the region picker; a region is {x, y, w, h} in the output's logical pixels.
export const STEP = 20;
export const MIN = 40;

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

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
