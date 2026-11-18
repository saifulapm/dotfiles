// Loaded with --import by a test that runs a CLI at a set instant: Date.now() and new Date() read FIXED_NOW, in the CLI and in each node it starts.
const now = Number(process.env.FIXED_NOW);
const RealDate = Date;
globalThis.Date = class extends RealDate {
  constructor(...args) {
    super(...(args.length ? args : [now]));
  }
  static now() {
    return now;
  }
};
