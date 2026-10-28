// dots-pointer X,Y,W,H OP...: niri's virtual pointer for the desktop skill, one process per gesture so a button pressed here is released here; X,Y,W,H is the box around every output in logical pixels, and the ops run in order: move X Y (exact, as niri maps x/W onto the box), down|up|click left|right|middle, scroll DX DY (wheel notches, down and right positive), wait MS, and pick (niri's pick-window under the pointer, printing its reply line; no reply in 500 ms exits 3); 1 is an error, 2 usage, and a compositor that stops answering ends the run 2 s past its waits.

#include <errno.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define PICK_MS 500

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwlr_virtual_pointer_v1 *pointer;
static struct wl_display *display;
static long box[4];
static long waited; // the ops' waits in ms, summed by the dry run

static void global(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version) {
    if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
    else if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
        manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void global_remove(void *data, struct wl_registry *reg, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {global, global_remove};

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void die(int code, const char *msg) {
    fprintf(stderr, "dots-pointer: %s\n", msg);
    exit(code);
}

static void on_alarm(int sig) {
    static const char msg[] = "dots-pointer: the compositor stopped answering\n";
    write(2, msg, sizeof msg - 1);
    _exit(1);
}

static long num(const char *s) {
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || *end || end == s)
        die(2, "not an integer");
    return v;
}

static uint32_t button(const char *s) {
    if (!strcmp(s, "left"))
        return BTN_LEFT;
    if (!strcmp(s, "right"))
        return BTN_RIGHT;
    if (!strcmp(s, "middle"))
        return BTN_MIDDLE;
    die(2, "button: left, right or middle");
    return 0;
}

// Each event is its own frame, sent and seen by niri before the next op.
static void frame(void) {
    zwlr_virtual_pointer_v1_frame(pointer);
    if (wl_display_roundtrip(display) < 0)
        die(1, "lost the Wayland connection");
}

static void press(uint32_t b, int state) {
    zwlr_virtual_pointer_v1_button(pointer, now_ms(), b, state);
    frame();
}

static void scroll(uint32_t axis, long notches) {
    if (!notches)
        return;
    zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
    zwlr_virtual_pointer_v1_axis_discrete(pointer, now_ms(), axis, wl_fixed_from_int(15 * notches), notches);
    frame();
}

static int niri_connect(const char *request) {
    const char *path = getenv("NIRI_SOCKET");
    if (!path || !*path)
        die(1, "NIRI_SOCKET is not set");
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof addr.sun_path)
        die(1, "NIRI_SOCKET is too long");
    strcpy(addr.sun_path, path);
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0 || connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0)
        die(1, "cannot reach niri's socket");
    size_t n = strlen(request);
    if (write(fd, request, n) != (ssize_t)n)
        die(1, "cannot write to niri's socket");
    return fd;
}

// Reads one reply line into buf until the deadline; returns its length, or -1 at the deadline.
static int read_line(int fd, char *buf, size_t cap, uint32_t deadline) {
    size_t len = 0;
    while (len < cap - 1) {
        int left = (int)(deadline - now_ms());
        if (left <= 0)
            return -1;
        struct pollfd p = {fd, POLLIN, 0};
        int r = poll(&p, 1, left);
        if (r < 0 && errno == EINTR)
            continue;
        if (r <= 0)
            return -1;
        ssize_t got = read(fd, buf + len, cap - 1 - len);
        if (got <= 0)
            break;
        len += got;
        if (memchr(buf, '\n', len))
            break;
    }
    buf[len] = 0;
    return len;
}

// niri installs the pick grab from an idle callback, so a press sent before that callback runs would reach the window under the pointer. A Layers request also answers from an idle callback, queued after the pick's because the pick request was written first, so once it answers the grab is in place.
static void pick(void) {
    static char buf[1 << 16];
    uint32_t deadline = now_ms() + PICK_MS;
    int fd = niri_connect("\"PickWindow\"\n");
    int sync = niri_connect("\"Layers\"\n");
    if (read_line(sync, buf, sizeof buf, deadline) < 0)
        die(3, "niri gave no answer in 500 ms");
    close(sync);
    press(BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
    press(BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    if (read_line(fd, buf, sizeof buf, deadline) <= 0)
        die(3, "niri gave no answer in 500 ms");
    close(fd);
    fputs(buf, stdout);
    fflush(stdout);
}

// Runs the ops, or with dry only checks them, so a bad op late in a list never leaves a button held.
static void run(int argc, char **argv, int dry) {
    for (int i = 2; i < argc; i++) {
        const char *op = argv[i];
        int left = argc - i - 1;
        if (!strcmp(op, "move") && left >= 2) {
            long x = num(argv[++i]) - box[0], y = num(argv[++i]) - box[1];
            if (x < 0 || y < 0 || x >= box[2] || y >= box[3])
                die(2, "point is outside the box");
            if (dry)
                continue;
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), x, y, box[2], box[3]);
            frame();
        } else if ((!strcmp(op, "down") || !strcmp(op, "up") || !strcmp(op, "click")) && left >= 1) {
            uint32_t b = button(argv[++i]);
            if (dry)
                continue;
            if (op[0] != 'u')
                press(b, WL_POINTER_BUTTON_STATE_PRESSED);
            if (op[0] != 'd')
                press(b, WL_POINTER_BUTTON_STATE_RELEASED);
        } else if (!strcmp(op, "scroll") && left >= 2) {
            long dx = num(argv[++i]), dy = num(argv[++i]);
            if (dry)
                continue;
            scroll(WL_POINTER_AXIS_VERTICAL_SCROLL, dy);
            scroll(WL_POINTER_AXIS_HORIZONTAL_SCROLL, dx);
        } else if (!strcmp(op, "wait") && left >= 1) {
            long ms = num(argv[++i]);
            if (ms < 0 || ms > 10000)
                die(2, "wait: 0 to 10000 ms");
            waited += ms;
            if (!dry)
                usleep(ms * 1000);
        } else if (!strcmp(op, "pick")) {
            if (!dry)
                pick();
        } else {
            die(2, "ops: move X Y, down|up|click B, scroll DX DY, wait MS, pick");
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 3)
        die(2, "usage: dots-pointer X,Y,W,H OP...");
    if (sscanf(argv[1], "%ld,%ld,%ld,%ld", &box[0], &box[1], &box[2], &box[3]) != 4 || box[2] <= 0 || box[3] <= 0)
        die(2, "box: X,Y,W,H in logical pixels");
    run(argc, argv, 1);
    signal(SIGALRM, on_alarm);
    alarm(2 + (waited + 999) / 1000);

    display = wl_display_connect(NULL);
    if (!display)
        die(1, "cannot reach the Wayland display");
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager)
        die(1, "the compositor has no zwlr_virtual_pointer_manager_v1");
    pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);

    run(argc, argv, 0);
    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
