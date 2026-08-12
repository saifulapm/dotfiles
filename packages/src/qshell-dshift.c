// qshell-dshift: double-tap-Shift watcher for the Notes quick capture
// (Copper's shift-shift summon, on a compositor that cannot bind modifier
// taps — niri binds are key chords only).
//
// Reads /dev/input keyboards (read-only, never grabs — every key still
// reaches the compositor and apps), detects two clean Shift taps within
// TAP_WINDOW_MS, and spawns ~/.dotfiles/bin/notes-quick-capture. A "clean
// tap" is Shift pressed and released with no other key in between, so
// Shift+letter typing never fires; any other key press also resets the
// pair, so type-Shift-type-Shift never fires either.
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

static void fire(void) {
    if (fork() == 0) {
        const char *home = getenv("HOME");
        char script[512];
        snprintf(script, sizeof(script), "%s/.dotfiles/bin/notes-quick-capture", home ? home : "");
        execl(script, script, (char *)NULL);
        _exit(127);
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

    int shift_down = 0;       // a Shift key is currently held
    int tap_clean = 0;        // no other key seen since it went down
    int64_t last_tap_end = 0; // when the last clean tap released

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
                        tap_clean = 0;
                        last_tap_end = 0;
                        continue;
                    }
                    if (ev[k].type != EV_KEY || ev[k].value == 2) // ignore autorepeat
                        continue;
                    int is_shift = ev[k].code == KEY_LEFTSHIFT || ev[k].code == KEY_RIGHTSHIFT;
                    if (!is_shift) {
                        // Any other key (including mouse buttons) breaks
                        // both the tap in progress and the pending pair.
                        tap_clean = 0;
                        last_tap_end = 0;
                        continue;
                    }
                    if (ev[k].value == 1) {
                        shift_down = 1;
                        tap_clean = 1;
                    } else if (ev[k].value == 0 && shift_down) {
                        shift_down = 0;
                        if (!tap_clean)
                            continue;
                        int64_t t = now_ms();
                        if (last_tap_end && t - last_tap_end <= TAP_WINDOW_MS) {
                            last_tap_end = 0;
                            fire();
                        } else {
                            last_tap_end = t;
                        }
                    }
                }
            }
        }
    }
}
