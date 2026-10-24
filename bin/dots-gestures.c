// dots-gestures [event-file...]: a four-finger pinch in opens the launcher and out toggles niri's overview; it reads the touchpads through libinput as niri does, so a swipe niri takes is never a pinch here, and a file of begin/update/end lines stands in for libinput.

#include <errno.h>
#include <fcntl.h>
#include <libinput.h>
#include <libudev.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define FINGERS 4
#define PINCH_IN 0.75
#define PINCH_OUT 1.33

static int replaying; // a replayed pinch waits for its command, so a file's pinches act in order

static int fingers; // fingers of the pinch under way, 0 if none
static double scale; // its scale relative to where it began

static void run(const char *const argv[]) {
    pid_t pid = fork();
    if (pid == 0) {
        execvp(argv[0], (char *const *)argv);
        _exit(127);
    }
    if (pid > 0 && replaying)
        waitpid(pid, NULL, 0);
}

static void begin(int n) {
    fingers = n;
    scale = 1.0;
}

static void update(double s) {
    scale = s;
}

static void end(int cancelled) {
    // Two-finger pinches zoom in apps, and three fingers are niri's swipes.
    if (fingers >= FINGERS && !cancelled) {
        if (scale <= PINCH_IN)
            run((const char *const[]){"dots-call", "launcher", "toggle", NULL});
        else if (scale >= PINCH_OUT)
            run((const char *const[]){"niri", "msg", "action", "toggle-overview", NULL});
    }
    fingers = 0;
}

static int replay(const char *path) {
    FILE *f = fopen(path, "re");
    if (!f) {
        perror(path);
        return 1;
    }
    char word[16];
    double value;
    while (fscanf(f, "%15s %lf", word, &value) == 2) {
        if (strcmp(word, "begin") == 0)
            begin((int)value);
        else if (strcmp(word, "update") == 0)
            update(value);
        else if (strcmp(word, "end") == 0)
            end((int)value);
    }
    fclose(f);
    return 0;
}

static int open_restricted(const char *path, int flags, void *data) {
    (void)data;
    int fd = open(path, flags | O_CLOEXEC);
    return fd < 0 ? -errno : fd;
}

static void close_restricted(int fd, void *data) {
    (void)data;
    close(fd);
}

static const struct libinput_interface interface = {open_restricted, close_restricted};

static int watch(void) {
    signal(SIGCHLD, SIG_IGN); // auto-reap the commands
    struct udev *udev = udev_new();
    struct libinput *li = udev ? libinput_udev_create_context(&interface, NULL, udev) : NULL;
    // The udev seat follows touchpads plugged in later, such as a Bluetooth trackpad.
    if (!li || libinput_udev_assign_seat(li, "seat0") != 0) {
        fprintf(stderr, "dots-gestures: libinput could not open seat0\n");
        return 1;
    }
    struct pollfd pfd = {libinput_get_fd(li), POLLIN, 0};
    for (;;) {
        libinput_dispatch(li);
        struct libinput_event *ev;
        while ((ev = libinput_get_event(li)) != NULL) {
            switch (libinput_event_get_type(ev)) {
            case LIBINPUT_EVENT_DEVICE_ADDED: {
                // Keyboards and mice have nothing for this watcher, so this context stops reading them; niri's own is untouched.
                struct libinput_device *d = libinput_event_get_device(ev);
                if (!libinput_device_has_capability(d, LIBINPUT_DEVICE_CAP_GESTURE))
                    libinput_device_config_send_events_set_mode(d, LIBINPUT_CONFIG_SEND_EVENTS_DISABLED);
                break;
            }
            case LIBINPUT_EVENT_GESTURE_PINCH_BEGIN:
                begin(libinput_event_gesture_get_finger_count(libinput_event_get_gesture_event(ev)));
                break;
            case LIBINPUT_EVENT_GESTURE_PINCH_UPDATE:
                update(libinput_event_gesture_get_scale(libinput_event_get_gesture_event(ev)));
                break;
            case LIBINPUT_EVENT_GESTURE_PINCH_END:
                end(libinput_event_gesture_get_cancelled(libinput_event_get_gesture_event(ev)));
                break;
            default:
                break;
            }
            libinput_event_destroy(ev);
        }
        if (poll(&pfd, 1, -1) < 0 && errno != EINTR)
            return 1;
    }
}

int main(int argc, char **argv) {
    if (argc < 2)
        return watch();
    replaying = 1;
    int status = 0;
    for (int a = 1; a < argc; a++)
        if (replay(argv[a]))
            status = 1;
    return status;
}
