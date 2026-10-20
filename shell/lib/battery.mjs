// The low-battery warning: once at 10% or less while discharging, armed again when the battery stops discharging or passes 15%, so one hovering at 10% warns once.
export function lowBattery(armed, fraction, discharging) {
  if (!discharging || fraction > 0.15) return { warn: false, armed: true };
  if (armed && fraction <= 0.1) return { warn: true, armed: false };
  return { warn: false, armed };
}
