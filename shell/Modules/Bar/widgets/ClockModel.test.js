// Unit tests for ClockModel.js's calendar grid. Run with:
//
//     node shell/Modules/Bar/widgets/ClockModel.test.js
//
// ClockModel.js is a `.pragma library` file, which node cannot parse, so it is
// loaded into a vm context with that line stripped (as AudioModel.test.js does).
//
// Zones that start DST at 00:00 have a calendar day with no local midnight, and
// the engines disagree about which side of the gap it falls on: Qt's V4 resolves
// it backward onto the previous date, node's V8 forward. Node therefore cannot
// see the duplicated day the shell draws (September 2026 in America/Santiago
// drew "30 31 1 2 3 4 5 | 5 6 7 …" under the shell's engine), so this pins the
// property that makes the question moot -- the grid is walked in UTC and never
// asks for a wall clock (omarchy d74d6ea2).

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "ClockModel.js"), "utf8").replace(/^\.pragma library$/m, "");
const panelSource = fs.readFileSync(path.join(__dirname, "CalendarPanel.qml"), "utf8");
const Model = vm.createContext({});
vm.runInContext(source, Model);

let failures = 0;
function test(name, fn) {
    try {
        fn();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures += 1;
        console.log(`FAIL  ${name}\n      ${error.message}`);
    }
}

// The vm context has its own Object prototype, so compare through JSON.
const plain = value => JSON.parse(JSON.stringify(value));
const days = (weeks, from, to) => plain(weeks.slice(from, to).flatMap(week => week.days.map(day => day.day)));

// The context's own Date, so the stand-in below is what the model's `new
// Date(...)` and `Date.UTC` resolve to while it is installed.
const RealDate = vm.runInContext("Date", Model);
class LocalTimeIsForbidden extends RealDate {
    constructor(...args) {
        if (args.length > 1)
            throw new Error("built a Date from local components");
        super(...args);
    }
    getFullYear() { throw new Error("read the local year"); }
    getMonth() { throw new Error("read the local month"); }
    getDate() { throw new Error("read the local day"); }
    getDay() { throw new Error("read the local weekday"); }
    setDate() { throw new Error("stepped the local day"); }
}

function withoutLocalTime(build) {
    Model.Date = LocalTimeIsForbidden;
    try {
        return { value: build(), localTimeUse: "" };
    } catch (error) {
        return { value: null, localTimeUse: error.message };
    } finally {
        delete Model.Date;
    }
}

test("the month grid is built without reading local time", () => {
    const september = withoutLocalTime(() => Model.monthGrid(2026, 8, 0, ""));
    assert.equal(september.localTimeUse, "");
    // Straight through the Chilean DST midnight of 6 September.
    assert.deepEqual(days(september.value, 0, 2), [30, 31, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
});

test("months are stepped without reading local time", () => {
    const stepped = withoutLocalTime(() => Model.stepMonth(2026, 8, 1));
    assert.equal(stepped.localTimeUse, "");
    assert.deepEqual(plain(stepped.value), { year: 2026, month: 9 });
});

test("stepping crosses the year in both directions", () => {
    assert.deepEqual(plain(Model.stepMonth(2026, 0, -1)), { year: 2025, month: 11 });
    assert.deepEqual(plain(Model.stepMonth(2025, 11, 1)), { year: 2026, month: 0 });
});

// Samoa skipped 30 December 2011 outright, a gap even V8 cannot paper over,
// so this one fails the old local walk under node too.
test("a day the local zone skipped is still drawn", () => {
    const previousTZ = process.env.TZ;
    process.env.TZ = "Pacific/Apia";
    try {
        const apia = Model.monthGrid(2011, 11, 1, "");
        assert.deepEqual(days(apia, 4, 5), [26, 27, 28, 29, 30, 31, 1]);
    } finally {
        if (previousTZ === undefined)
            delete process.env.TZ;
        else
            process.env.TZ = previousTZ;
    }
});

test("every grid is six rows of seven consecutive days", () => {
    for (let month = 0; month < 12; month++) {
        const weeks = Model.monthGrid(2026, month, 1, "");
        assert.equal(weeks.length, 6);
        const keys = weeks.flatMap(week => week.days.map(day => day.key));
        for (let i = 1; i < keys.length; i++)
            assert.equal(Date.parse(keys[i]) - Date.parse(keys[i - 1]), 86400000, `${keys[i - 1]} -> ${keys[i]}`);
    }
});

test("the heading names its month from a noon that always exists", () => {
    assert.match(panelSource, /viewDate: new Date\(viewYear, viewMonth, 1, 12\)/);
});

console.log(failures === 0 ? "\nall ClockModel tests passed" : `\n${failures} failing`);
process.exit(failures === 0 ? 0 : 1);
