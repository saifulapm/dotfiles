// What bin/dots-pinentry and the shell's card say to each other: one request line, with gpg's Assuan text still percent-escaped, and the Assuan answer the stub hands gpg as it is.
import { line } from './voice.mjs';

export const CANCEL = 'ERR 83886179 Operation cancelled\n';
export const ALLOW = 'OK\n';
export const DENY = 'ERR 83886194 Not confirmed\n';
const KINDS = ['passphrase', 'confirm'];

// %XX is a byte; runs of bytes decode as UTF-8, and a run that is not UTF-8 reads byte by byte.
function unescape(s) {
  return s.replace(/(%[0-9A-Fa-f]{2})+/g, (run) => {
    try {
      return decodeURIComponent(run);
    } catch (e) {
      return run.replace(/%([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
    }
  });
}

// "<kind>\t<description>\t<prompt>\t<error>", or null for anything else, such as the stub's empty probe.
export function parseRequest(text) {
  const f = String(text).split('\t');
  if (f.length !== 4 || KINDS.indexOf(f[0]) < 0) return null;
  return { kind: f[0], description: unescape(f[1]), prompt: unescape(f[2]), error: unescape(f[3]) };
}

// The passphrase on one Assuan data line: %, CR, LF and the other controls escaped, the rest as typed.
export function pinAnswer(pin) {
  return 'D ' + pin.replace(/[%\x00-\x1f\x7f]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')) + '\nOK\n';
}

// gpg-agent's "Bad Passphrase (try 2 of 3)" as the board writes it.
export function errorLine(text) {
  const m = line(text).match(/^Bad Passphrase \(try (\d+) of (\d+)\)$/i);
  return m ? `Bad passphrase · try ${m[1]} of ${m[2]}` : line(text);
}

// The heading in the launcher's label idiom (Blueprint's header names gpg) and the key strip.
export function cardText(look, kind) {
  const name = kind === 'confirm' ? 'confirm' : 'passphrase';
  return {
    heading: look.label.kind === 'header' ? look.heading('gpg', name) : look.heading(name, ''),
    keys: look.keys(kind === 'confirm' ? [['↵', 'allow'], ['esc', 'deny']] : [['↵', 'unlock'], ['esc', 'cancel']]),
  };
}
