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

// Whether a press at x, y in item lands on a surface's card: a drawn item under it, however deep, is named card; holders are searched whatever their own size.
export function onCard(item, x, y) {
  for (const child of item.children) {
    if (!child.visible) continue;
    const p = item.mapToItem(child, x, y);
    if (child.objectName === 'card' ? p.x >= 0 && p.y >= 0 && p.x < child.width && p.y < child.height : onCard(child, p.x, p.y)) return true;
  }
  return false;
}
