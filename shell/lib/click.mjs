// The drawn click area a check names, searched from item down past every hidden page, or null.
export function clickArea(item, name) {
  for (const child of item.children) {
    if (!child.visible) continue;
    if (child.objectName === 'click:' + name) return child;
    const found = clickArea(child, name);
    if (found) return found;
  }
  return null;
}

// Where that click area is drawn in root's coordinates, as the JSON a box call answers: {x, y, w, h}, or null.
export function boxJson(root, name) {
  const area = clickArea(root, name);
  if (!area) return 'null';
  const at = area.mapToItem(root, 0, 0);
  return JSON.stringify({ x: at.x, y: at.y, w: area.width, h: area.height });
}
