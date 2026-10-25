// A virtual pointer for nested checks: it reads press, move, release, click, wheel and sleep lines on stdin and holds one pointer from press to release.
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_seat *seat;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
	if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
		manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
	else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat)
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener listener = {global, global_remove};

static uint32_t now_ms(void) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void pause_ms(long ms) {
	struct timespec t = {ms / 1000, (ms % 1000) * 1000000};
	nanosleep(&t, NULL);
}

int main(int argc, char **argv) {
	if (argc != 3) {
		fprintf(stderr, "usage: pointer WIDTH HEIGHT < commands\n");
		return 2;
	}
	// Absolute motion is a fraction of this extent, so with one output it lands in output pixels.
	uint32_t width = atoi(argv[1]), height = atoi(argv[2]);
	struct wl_display *display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "pointer: no Wayland display\n");
		return 1;
	}
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &listener, NULL);
	wl_display_roundtrip(display);
	if (!manager) {
		fprintf(stderr, "pointer: the compositor has no zwlr_virtual_pointer_manager_v1\n");
		return 1;
	}
	struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
	double x = 0, y = 0;
	char line[256];
	setvbuf(stdout, NULL, _IOLBF, 0);
	while (fgets(line, sizeof line, stdin)) {
		char cmd[16] = "";
		double tx = 0, ty = 0;
		int steps = 1;
		int n = sscanf(line, "%15s %lf %lf %d", cmd, &tx, &ty, &steps);
		if (n < 1)
			continue;
		if (strcmp(cmd, "sleep") == 0) {
			pause_ms((long)tx);
		} else if (strcmp(cmd, "press") == 0 || strcmp(cmd, "move") == 0) {
			// A move goes in steps 15 ms apart, so the client sees it cross its drag threshold and the compositor sends drag motion.
			if (strcmp(cmd, "press") == 0 || steps < 1)
				steps = 1;
			for (int i = 1; i <= steps; i++) {
				double px = x + (tx - x) * i / steps, py = y + (ty - y) * i / steps;
				zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), (uint32_t)px, (uint32_t)py, width, height);
				zwlr_virtual_pointer_v1_frame(pointer);
				wl_display_roundtrip(display);
				if (steps > 1)
					pause_ms(15);
			}
			x = tx;
			y = ty;
			if (strcmp(cmd, "press") == 0) {
				pause_ms(50);
				zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
				zwlr_virtual_pointer_v1_frame(pointer);
			}
		} else if (strcmp(cmd, "click") == 0) {
			// A click is a move, a press and a release, the button held 50 ms as a hand holds it.
			zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), (uint32_t)tx, (uint32_t)ty, width, height);
			zwlr_virtual_pointer_v1_frame(pointer);
			wl_display_roundtrip(display);
			x = tx;
			y = ty;
			pause_ms(50);
			zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
			zwlr_virtual_pointer_v1_frame(pointer);
			wl_display_roundtrip(display);
			pause_ms(50);
			zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
			zwlr_virtual_pointer_v1_frame(pointer);
		} else if (strcmp(cmd, "wheel") == 0) {
			// wheel N turns a mouse wheel N notches where the pointer is, down when N is positive, one frame per notch; a notch is 15 as libinput reports one.
			int notches = (int)tx;
			for (int i = 0; i < abs(notches); i++) {
				int dir = notches > 0 ? 1 : -1;
				zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
				zwlr_virtual_pointer_v1_axis_discrete(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(15 * dir), dir);
				zwlr_virtual_pointer_v1_frame(pointer);
				wl_display_roundtrip(display);
				pause_ms(30);
			}
		} else if (strcmp(cmd, "release") == 0) {
			zwlr_virtual_pointer_v1_button(pointer, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
			zwlr_virtual_pointer_v1_frame(pointer);
		} else {
			fprintf(stderr, "pointer: unknown command %s\n", cmd);
			continue;
		}
		wl_display_roundtrip(display);
		printf("done %s\n", cmd);
	}
	zwlr_virtual_pointer_v1_destroy(pointer);
	wl_display_roundtrip(display);
	wl_display_disconnect(display);
	return 0;
}
