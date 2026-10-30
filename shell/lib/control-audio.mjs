// Control Audio's app rows, from Quickshell's stream nodes and link groups, and each device's profiles and ports, from pw-dump's JSON.

// Filter chains, loopbacks and peak monitors are output streams too, but plumbing, not apps.
function isApp(props) {
  return props['media.class'] === 'Stream/Output/Audio' && !props['node.passive'] && !props['node.link-group'] && !props['stream.monitor'];
}

// Each playing app as {id, sink}: an output stream with an active link to one of the sinks, in the streams' order.
export function appStreams(streams, links, sinkIds) {
  const out = [];
  for (const s of streams) {
    if (!isApp(s.props ?? {})) continue;
    const link = links.find(l => l.active && l.source === s.id && sinkIds.includes(l.target));
    if (link) out.push({ id: s.id, sink: link.target });
  }
  return out;
}

export function appTitle(props) {
  return props['application.name'] || props['node.description'] || props['node.name'] || '';
}

export function appRow(app) {
  return { title: app.title, detail: [app.sink, app.muted ? 'muted' : Math.round(app.volume * 100) + '%'].join(' · ') };
}

// The output after the app's own, wrapping from the last to the first.
export function nextSink(sinkIds, current) {
  if (!sinkIds.length) return null;
  return sinkIds[(sinkIds.indexOf(current) + 1) % sinkIds.length];
}

// Every device in a pw-dump, by id: its profiles and routes, and the ones it has on now.
export function devices(dump) {
  const out = {};
  for (const o of dump) {
    if (o.type !== 'PipeWire:Interface:Device') continue;
    const p = o.info?.params ?? {};
    out[o.id] = { profiles: p.EnumProfile ?? [], profile: (p.Profile ?? [])[0] ?? null, routes: p.EnumRoute ?? [], active: p.Route ?? [] };
  }
  return out;
}

function after(items, current) {
  if (!items.length) return null;
  const next = items[(items.findIndex(i => i.index === current) + 1) % items.length];
  return next.index === current ? null : next.index;
}

// The profile p moves to, never off or one the device says is unavailable; null when there is no other.
export function nextProfile(device) {
  const usable = device.profiles.filter(p => p.name !== 'off' && p.available !== 'no');
  return after(usable, device.profile?.index);
}

// A node's routes: those of its direction on its own card device, as set-route takes them for that node.
function nodeRoutes(device, direction, cardDevice) {
  return device.routes.filter(r => r.direction === direction && (cardDevice == null || (r.devices ?? []).includes(cardDevice)));
}

function activeRoute(device, direction, cardDevice) {
  return device.active.find(r => r.direction === direction && (cardDevice == null || r.device === cardDevice)) ?? null;
}

// The port r moves to, never one the device says is unavailable; null when there is no other.
export function nextRoute(device, direction, cardDevice) {
  const usable = nodeRoutes(device, direction, cardDevice).filter(r => r.available !== 'no');
  return after(usable, activeRoute(device, direction, cardDevice)?.index);
}

// The profile and port a row's detail adds, as the device describes them; ALSA describes HiFi as Default, which says nothing beside the row's own default.
export function deviceParts(device, direction, cardDevice) {
  const p = device.profile;
  const profile = p && (p.description === 'Default' ? p.name : p.description);
  return [profile, activeRoute(device, direction, cardDevice)?.description].filter(Boolean);
}

// A change that fails, as on a device removed a moment before, leaves the row as it was and says so in the island for 1.5 s.
export function changeToast(exitCode) {
  return exitCode === 0 ? null : 'Audio change failed';
}
