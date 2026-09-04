// qshell-dshift: double-tap-modifier watcher, on a compositor that cannot bind
// modifier taps — niri binds are key chords only.
//
//   Shift Shift  →  ~/.dotfiles/bin/notes-quick-capture   (Copper's summon)
//   Alt Alt      →  ~/.dotfiles/bin/voxtype-toggle        (start/stop dictation)
//
// Reads /dev/input keyboards (read-only, never grabs — every key still
// reaches the compositor and apps), detects two clean taps of the SAME
// modifier within TAP_WINDOW_MS, and spawns that modifier's script. A "clean
// tap" is the modifier pressed and released with no other key in between, so
// Shift+letter and Alt+Tab never fire; any other key press also resets the
// pair, so type-Shift-type-Shift never fires either. The modifiers reset each
// other too — Shift-then-Alt is a chord, not half of two pairs.
//
// THE NAME IS HISTORICAL. It watched only Shift when it was written
// (2026-08-13); Alt-Alt joined it 2026-09-04 when the voxtype keybinds moved
// off Mod+Ctrl+X / F9. Extending this rather than shipping a second watcher is
// the whole point: the event stream, the poll loop and the device rescan are
// already here, and a second always-on service would double the wakeups on
// every keystroke to read the same events again. Renaming the binary would
// mean renaming the unit, which leaves an orphaned enabled service on every
// machine that already has the old one — not worth it for a filename.
//
// Written in C for the resident cost: this is an always-on user service,
// and it idles under 1 MB where a python watcher parks ~10 MB. Built by
// run_after_34-dshift.sh; needs the `input` group (or an ACL) to read the
// devices. Note wtype/virtual-keyboard input is invisible here — this
// watches evdev, physical keyboards only.

#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define MAX_DEVS 32
#define TAP_WINDOW_MS 400

// One watched modifier: its two keycodes, the script its double-tap runs, and
// the state machine for the pair in progress.
typedef struct {
    int lcode;
    int rcode;
    const char *script; // relative to $HOME
    int down;           // one of the two is currently held
    int clean;          // no other key seen since it went down
    int64_t last_end;   // when the previous clean tap released, 0 if none
} tap_t;

static tap_t taps[] = {
    {KEY_LEFTSHIFT, KEY_RIGHTSHIFT, "/.dotfiles/bin/notes-quick-capture", 0, 0, 0},
    // Alt rather than a chord because it is the one modifier a hand can hit
    // twice without leaving the home position, and dictation is started far
    // more often than anything else bound here. Both Alts count, matching
    // Shift: AltGr is safe because it is only ever used as a chord, which the
    // clean-tap rule already rejects.
    {KEY_LEFTALT, KEY_RIGHTALT, "/.dotfiles/bin/voxtype-toggle", 0, 0, 0},
};

#define NTAPS ((int)(sizeof(taps) / sizeof(taps[0])))

static struct pollfd fds[MAX_DEVS + 1]; // [0] is the inotify fd
static int nfds = 1;

static int has_key(int fd, int code) {
    unsigned char bits[KEY_MAX / 8 + 1];
    memset(bits, 0, sizeof(bits));
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) < 0)
        return 0;
    return (bits[code / 8] >> (code % 8)) & 1;
}

static void scan_devices(void) {
    for (int i = 1; i < nfds; i++)
        if (fds[i].fd >= 0)
            close(fds[i].fd);
    nfds = 1;
    DIR *dir = opendir("/dev/input");
    if (!dir)
        return;
    struct dirent *e;
    while ((e = readdir(dir)) != NULL && nfds < MAX_DEVS + 1) {
        if (strncmp(e->d_name, "event", 5) != 0)
            continue;
        char path[300];
        snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        // Keyboards AND pointer devices: a shift+click chord spans two
        // devices, and without the mouse open a double shift-click would
        // read as two clean taps and fire (review 2026-08-13). Anything
        // with neither Shift nor a button is noise.
        if (!has_key(fd, KEY_LEFTSHIFT) && !has_key(fd, BTN_LEFT)) {
            close(fd);
            continue;
        }
        fds[nfds].fd = fd;
        fds[nfds].events = POLLIN;
        fds[nfds].revents = 0;
        nfds++;
    }
    closedir(dir);
}

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void fire(const char *relative) {
    if (fork() == 0) {
        const char *home = getenv("HOME");
        char script[512];
        snprintf(script, sizeof(script), "%s%s", home ? home : "", relative);
        execl(script, script, (char *)NULL);
        _exit(127);
    }
}

// Any key that is not part of modifier `except` breaks every pending pair it
// is not part of. Passing -1 means "a plain key: break all of them".
static void reset_others(int except) {
    for (int i = 0; i < NTAPS; i++) {
        if (i == except)
            continue;
        taps[i].clean = 0;
        taps[i].last_end = 0;
    }
}

int main(void) {
    signal(SIGCHLD, SIG_IGN); // auto-reap the capture script

    int ifd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (ifd >= 0)
        inotify_add_watch(ifd, "/dev/input", IN_CREATE | IN_DELETE | IN_ATTRIB);
    fds[0].fd = ifd;
    fds[0].events = POLLIN;

    scan_devices();

    for (;;) {
        if (poll(fds, (nfds_t)nfds, -1) < 0)
            continue;

        if (ifd >= 0 && (fds[0].revents & POLLIN)) {
            char buf[4096];
            while (read(ifd, buf, sizeof(buf)) > 0) {
            }
            // Settle before rescanning: a fresh device node gets its
            // group/ACL a beat after IN_CREATE.
            usleep(200000);
            scan_devices();
            continue;
        }

        for (int i = 1; i < nfds; i++) {
            if (fds[i].fd < 0 || !(fds[i].revents & (POLLIN | POLLERR | POLLHUP)))
                continue;
            if (fds[i].revents & (POLLERR | POLLHUP)) {
                close(fds[i].fd); // unplugged; inotify already queued a rescan
                fds[i].fd = -1;
                continue;
            }
            struct input_event ev[16];
            ssize_t n;
            while ((n = read(fds[i].fd, ev, sizeof(ev))) > 0) {
                int cnt = (int)(n / sizeof(struct input_event));
                for (int k = 0; k < cnt; k++) {
                    // Shift+scroll is a chord too; wheel events are EV_REL,
                    // invisible to the key path. Plain motion (REL_X/Y) is
                    // deliberately NOT a reset — hands drift between taps.
                    if (ev[k].type == EV_REL && (ev[k].code == REL_WHEEL || ev[k].code == REL_HWHEEL || ev[k].code == REL_WHEEL_HI_RES || ev[k].code == REL_HWHEEL_HI_RES)) {
                        reset_others(-1);
                        continue;
                    }
                    if (ev[k].type != EV_KEY || ev[k].value == 2) // ignore autorepeat
                        continue;

                    int which = -1;
                    for (int m = 0; m < NTAPS; m++)
                        if (ev[k].code == taps[m].lcode || ev[k].code == taps[m].rcode)
                            which = m;

                    if (which < 0) {
                        // Any other key (including mouse buttons) breaks
                        // every tap in progress and every pending pair.
                        reset_others(-1);
                        continue;
                    }

                    // A watched modifier is still "another key" to the OTHER
                    // watched modifiers: Shift-then-Alt is a chord, and must
                    // not leave half a Shift pair armed behind it.
                    reset_others(which);

                    tap_t *tap = &taps[which];
                    if (ev[k].value == 1) {
                        tap->down = 1;
                        tap->clean = 1;
                    } else if (ev[k].value == 0 && tap->down) {
                        tap->down = 0;
                        if (!tap->clean)
                            continue;
                        int64_t t = now_ms();
                        if (tap->last_end && t - tap->last_end <= TAP_WINDOW_MS) {
                            tap->last_end = 0;
                            fire(tap->script);
                        } else {
                            tap->last_end = t;
                        }
                    }
                }
            }
        }
    }
}
