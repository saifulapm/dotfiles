// The theme switcher's cursor and card captions; pure, so node tests what the shell imports.
export function step(names, name, by) {
  const i = Math.max(0, Math.min(names.length - 1, names.indexOf(name) + by));
  return names[i];
}

export function summary(t) {
  const frame = t.primitive.frame === 'none' ? 'no frame' : t.primitive.frame;
  const shadow = t.primitive.shadow === 'hard-offset' ? 'hard' : t.primitive.shadow === 'none' ? 'no' : t.primitive.shadow;
  return `${t.mode} · ${frame} · ${shadow} shadow`;
}
