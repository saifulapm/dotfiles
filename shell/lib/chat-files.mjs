// Files, pasted text and images a chat message carries, held to the sizes the model and the shell can take.
export const TEXT_MAX = 512 * 1024;
export const IMAGE_MAX = 5 * 1024 * 1024;
export const VISION_MODEL = 'amd/DeepSeek-V4-Flash-Vision-Exp';

const IMAGE_EXT = /\.(png|jpe?g|gif|webp)$/i;

export function isImage(name) {
  return IMAGE_EXT.test(String(name));
}

// Whole KiB under 1 MiB (any non-empty file reads at least 1 KiB), then MiB with one decimal that drops a trailing .0.
export function sizeText(bytes) {
  if (bytes >= 1024 * 1024) return String(Math.round((bytes / (1024 * 1024)) * 10) / 10) + ' MiB';
  if (bytes <= 0) return '0 KiB';
  return Math.max(1, Math.round(bytes / 1024)) + ' KiB';
}

// null when the file fits, else one line that names the limit.
export function check({ name, kind, size }) {
  const max = kind === 'image' ? IMAGE_MAX : TEXT_MAX;
  if (size <= max) return null;
  return `${name} is ${sizeText(size)}, over the ${sizeText(max)} limit`;
}

export function chipText({ name, size }) {
  return `${name} · ${sizeText(size)}`;
}

const hasImage = (attachments) => (attachments || []).some((a) => a.kind === 'image');

export function modelFor(alias, attachments) {
  return hasImage(attachments) ? VISION_MODEL : alias;
}

export function pillText(alias, attachments) {
  return hasImage(attachments) ? 'vision · ' + VISION_MODEL : alias;
}

// Text files ride inside the message as fenced blocks; images become parts, which is the shape the vision model reads.
export function content(text, attachments) {
  const list = attachments || [];
  const blocks = list.filter((a) => a.kind !== 'image').map((a) => `\n\n\`\`\`${a.name}\n${a.text}\n\`\`\``);
  const body = text + blocks.join('');
  const images = list.filter((a) => a.kind === 'image');
  if (!images.length) return body;
  return [{ type: 'text', text: body }, ...images.map((a) => ({ type: 'image_url', image_url: { url: a.data } }))];
}
