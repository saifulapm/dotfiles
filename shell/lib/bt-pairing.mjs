// Pure pieces of a Bluetooth pairing request from bin/dots-bt-agent, which the island asks as a question, kept here so node can test them.
import { line } from './voice.mjs';

const KINDS = ['confirm', 'display', 'pin', 'passkey', 'authorize'];
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const MARK = /[‎‏؜‪-‮⁦-⁩]/g;
const str = (v) => (typeof v === 'string' ? v : '');
// A device sends its own name, so it is drawn as one line of plain text.
const oneLine = (s) => line(str(s).replace(CONTROL, ' ').replace(MARK, ''));

// BlueZ's codes are six digits, a confirm's may be empty (RequestAuthorization) and a service is a 128-bit UUID, so a line that breaks this did not come from the agent.
const SIX = /^[0-9]{6}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// A name is up to 248 bytes, which would wrap the question past its code.
const NAME_MAX = 40;

// A device's name as one line, cut to fit, or its address when it sent none.
export function deviceName(name, address) {
  const n = oneLine(name);
  return n.length > NAME_MAX ? n.slice(0, NAME_MAX - 1) + '…' : n || oneLine(address);
}

export function parseRequest(text) {
  let r;
  try {
    r = JSON.parse(String(text));
  } catch (e) {
    return null;
  }
  if (!r || typeof r !== 'object' || Array.isArray(r) || KINDS.indexOf(r.kind) < 0) return null;
  const address = oneLine(r.address);
  const device = deviceName(r.device, r.address);
  const code = str(r.code);
  const service = str(r.service);
  if (!device) return null;
  if (r.kind === 'display' && !SIX.test(code)) return null;
  if (r.kind === 'confirm' && code !== '' && !SIX.test(code)) return null;
  if (r.kind === 'authorize' && !UUID.test(service)) return null;
  return { kind: r.kind, device: device, address: address, code: code, service: service };
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
