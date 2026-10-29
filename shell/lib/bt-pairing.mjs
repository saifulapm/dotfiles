// Pure pieces of a Bluetooth pairing request from bin/dots-bt-agent, which the island asks as a question, kept here so node can test them.
import { line } from './voice.mjs';

const KINDS = ['confirm', 'display', 'pin', 'passkey', 'authorize'];
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const MARK = /[‎‏؜‪-‮⁦-⁩]/g;
const str = (v) => (typeof v === 'string' ? v : '');
// A device sends its own name, so it is drawn as one line of plain text.
const oneLine = (s) => line(str(s).replace(CONTROL, ' ').replace(MARK, ''));

export function parseRequest(text) {
  let r;
  try {
    r = JSON.parse(String(text));
  } catch (e) {
    return null;
  }
  if (!r || typeof r !== 'object' || Array.isArray(r) || KINDS.indexOf(r.kind) < 0) return null;
  const address = oneLine(r.address);
  return {
    kind: r.kind,
    device: oneLine(r.device) || address,
    address: address,
    code: str(r.code).replace(/\D/g, ''),
    service: str(r.service),
  };
}

// The services a device asks for most, by their 16-bit number on the Bluetooth base UUID.
const SERVICES = {
  '1101': 'Serial port',
  '1105': 'File push',
  '1106': 'File transfer',
  '1108': 'Headset',
  '110a': 'Audio',
  '110b': 'Audio',
  '110c': 'Remote control',
  '110d': 'Audio',
  '110e': 'Remote control',
  '1112': 'Headset',
  '1115': 'Network',
  '1116': 'Network',
  '111e': 'Hands-Free',
  '111f': 'Hands-Free',
  '1124': 'Keyboard and mouse',
  '112f': 'Contacts',
  '1132': 'Messages',
  '1200': 'Device information',
};

export function serviceName(uuid) {
  const u = oneLine(uuid).replace(/ /g, '').toLowerCase();
  const short = /^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$/.exec(u);
  if (short) return SERVICES[short[1]] ?? `service 0x${short[1]}`;
  return `service ${u}`;
}

export function promptText(r) {
  switch (r.kind) {
    case 'confirm':
      return r.code ? `Pair ${r.device}? ${r.code}` : `Pair ${r.device}?`;
    case 'display':
      return `Type ${r.code} on ${r.device}`;
    case 'pin':
      return `PIN for ${r.device}`;
    case 'passkey':
      return `Passkey for ${r.device}`;
    default:
      return `${r.device} wants ${serviceName(r.service)}`;
  }
}

export function keyText(kind) {
  switch (kind) {
    case 'confirm':
      return [['↵', 'yes'], ['esc', 'no']];
    case 'display':
      return [['esc', 'cancel']];
    case 'authorize':
      return [['↵', 'allow'], ['esc', 'deny']];
    default:
      return [['↵', 'send'], ['esc', 'cancel']];
  }
}

// A legacy PIN is up to 16 characters; a passkey is a number up to 999999.
export function typed(kind, pin, text) {
  if (kind === 'pin') return /^[\x21-\x7e]$/.test(text) && pin.length < 16 ? pin + text : pin;
  if (kind === 'passkey') return /^[0-9]$/.test(text) && pin.length < 6 ? pin + text : pin;
  return pin;
}

export const answerLine = (kind, ok, pin) => JSON.stringify(ok && (kind === 'pin' || kind === 'passkey') ? { ok: true, pin: pin } : { ok: ok }) + '\n';

// Quickshell gives QML no error from a pair, so a pair failed when its pairing stops with the device still unpaired.
export const pairFailed = (was, now) => was.pairing && !now.pairing && !now.paired;
