// dots-dshift [-i <id>] [event-file...]: two clean Shift taps run qs ipc call notes capture; it reads evdev without grabbing, and files stand in for /dev/input.

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
#include <sys/wait.h>
#include <unistd.h>

#define MAX_DEVS 32
#define TAP_WINDOW_MS 400

static const char *instance; // value of -i, or NULL

static int down;       // a Shift is currently held
static int clean;      // no other key seen since it went down
static int64_t last_end; // when the previous clean tap released, 0 if none

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
        // Pointer devices too: without the mouse open, a double shift-click reads as two clean taps.
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

static void fire(void) {
    if (fork() == 0) {
        if (instance)
            execlp("qs", "qs", "ipc", "-i", instance, "call", "notes", "capture", (char *)NULL);
        else
            execlp("qs", "qs", "ipc", "call", "notes", "capture", (char *)NULL);
        _exit(127);
    }
}

static void feed(const struct input_event *ev) {
    // Shift+scroll is a chord too. Plain motion is not a reset: hands drift between taps.
    if (ev->type == EV_REL && (ev->code == REL_WHEEL || ev->code == REL_HWHEEL || ev->code == REL_WHEEL_HI_RES || ev->code == REL_HWHEEL_HI_RES)) {
        clean = 0;
        last_end = 0;
        return;
    }
    if (ev->type != EV_KEY || ev->value == 2) // autorepeat
        return;

    if (ev->code != KEY_LEFTSHIFT && ev->code != KEY_RIGHTSHIFT) {
        // Any other key, mouse buttons included, breaks the tap and the pair.
        clean = 0;
        last_end = 0;
        return;
    }

    if (ev->value == 1) {
        down = 1;
        clean = 1;
    } else if (ev->value == 0 && down) {
        down = 0;
        if (!clean)
            return;
        // The event's own time, so a replayed file behaves like live input.
        int64_t t = (int64_t)ev->time.tv_sec * 1000 + ev->time.tv_usec / 1000;
        if (last_end && t - last_end <= TAP_WINDOW_MS) {
            last_end = 0;
            fire();
        } else {
            last_end = t;
        }
    }
}

static int replay(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        perror(path);
        return 1;
    }
    struct input_event ev;
    while (read(fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev))
        feed(&ev);
    close(fd);
    return 0;
}

static void watch(void) {
    signal(SIGCHLD, SIG_IGN); // auto-reap the capture command

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
            // A fresh device node gets its group/ACL a beat after IN_CREATE.
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
                for (int k = 0; k < cnt; k++)
                    feed(&ev[k]);
            }
        }
    }
}

int main(int argc, char **argv) {
    int a = 1;
    if (a + 1 < argc && strcmp(argv[a], "-i") == 0) {
        instance = argv[a + 1];
        a += 2;
    }
    if (a >= argc)
        watch();

    int status = 0;
    for (; a < argc; a++)
        if (replay(argv[a]))
            status = 1;
    while (wait(NULL) > 0) {
    }
    return status;
}
