// What Files writes, in each theme's voice; its listing, sizes and preview come from picker.mjs.
import { oneLine } from './picker.mjs';

// The folder's own name: the window's title, which the margin draws beside the app id.
export function folderName(home, folder) {
  if (folder === home) return 'Home';
  if (folder === '/') return '/';
  return oneLine(folder.slice(folder.lastIndexOf('/') + 1));
}

// Paper's caps label and ink chip, Artboard's Files and Mod+Y, Blueprint's bracketed key.
export function headText(voice, home, folder) {
  const folderText = folderName(home, folder);
  if (voice === 'caps') return { label: 'FILES', folder: folderText, chip: 'MOD Y' };
  return { label: 'Files', folder: folderText, chip: voice === 'bracket' ? '[MOD+Y]' : 'Mod+Y' };
}
