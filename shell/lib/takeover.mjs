// A prompt that holds another process's socket (polkit, gpg, pairing, the file picker) takes the island over the surface open in it, and hands it back once answered, cancelled or hung up (7E95CSV2). The prompts showing are a stack of names, oldest first.

// A prompt that shows goes on top, once.
export const push = (stack, name) => stack.filter((n) => n !== name).concat([name]);

export const drop = (stack, name) => stack.filter((n) => n !== name);

// What the island draws: the newest prompt, else the open surface, else nothing.
export const holder = (surface, stack) => (stack.length ? stack[stack.length - 1] : surface ?? null);

// What the shown prompt hands the island back to: the prompt before it, else the surface; null over the resting island.
export const under = (surface, stack) => (stack.length > 1 ? stack[stack.length - 2] : surface ?? null);

// Notifications, questions and media changes wait while anything holds the island.
export const holds = (surface, stack) => !!surface || stack.length > 0;

const NAMES = {
  launcher: 'Launcher',
  notifs: 'Notifications',
  cheatsheet: 'Keys',
  control: 'Control',
  record: 'Recorder',
  pass: 'Pass',
  tailscale: 'Tailscale',
  accounts: 'Accounts',
  dns: 'DNS Shield',
  goals: 'Goals',
  polkit: 'Authenticate',
  pinentry: 'GPG',
  pairing: 'Bluetooth',
  picker: 'Files',
};

// The chip a prompt's header draws for what it returns to.
export const chipText = (name) => (name ? NAMES[name] ?? name : '');

// A prompt that takes the keyboard mid-typing ignores Enter for its first half second, so a key meant for another window answers nothing (29PTQZ0V); a click still answers at once.
export const ENTER_GUARD_MS = 500;
export const enterReady = (shownAt, now) => shownAt > 0 && now - shownAt >= ENTER_GUARD_MS;
