// The words of Dekho's toasts that are worked out rather than written in a page.
import { facets, kindName } from './dekho-browse.mjs';

export const FILTERS_CLEARED = 'Filters cleared';

// The toast for a facet that just changed: its value as the facet box writes it, and an unset facet as "any <facet>".
export function filterToast(f, facet) {
  if (facet === 'kind') return `Filter: ${kindName(f.kind)}`;
  const box = facets(f).find(([, name]) => name.toLowerCase() === facet);
  return box[2] === 'Any' ? `Filter: any ${facet}` : `Filter: ${box[2]}`;
}
