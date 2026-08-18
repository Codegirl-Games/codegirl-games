#define _POSIX_C_SOURCE 199309L

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum {
    WINDOW_WIDTH = 640,
    WINDOW_HEIGHT = 480,
    SQUARE_SIZE = 50,
};

static double monotonic_seconds(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        perror("clock_gettime");
        exit(1);
    }
    return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}

static void set_key_state(KeySym key, bool down, bool *left, bool *right,
                          bool *up, bool *down_key) {
    switch (key) {
    case XK_Left:
        *left = down;
        break;
    case XK_Right:
        *right = down;
        break;
    case XK_Up:
        *up = down;
        break;
    case XK_Down:
        *down_key = down;
        break;
    default:
        break;
    }
}

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fputs("unable to open X display\n", stderr);
        return 1;
    }

    int screen = DefaultScreen(display);
    Window window = XCreateSimpleWindow(
        display, RootWindow(display, screen), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT,
        0, BlackPixel(display, screen), BlackPixel(display, screen));
    XStoreName(display, window, "Agentbox Mover");
    XSelectInput(display, window,
                 ExposureMask | KeyPressMask | KeyReleaseMask | ButtonPressMask);
    XMapWindow(display, window);

    GC gc = XCreateGC(display, window, 0, NULL);
    Colormap colors = DefaultColormap(display, screen);
    XColor green;
    XColor red;
    if (!XParseColor(display, colors, "#00ff66", &green) ||
        !XAllocColor(display, colors, &green) ||
        !XParseColor(display, colors, "#ff3355", &red) ||
        !XAllocColor(display, colors, &red)) {
        fputs("unable to allocate colors\n", stderr);
        XCloseDisplay(display);
        return 1;
    }

    double x = (WINDOW_WIDTH - SQUARE_SIZE) / 2.0;
    double y = (WINDOW_HEIGHT - SQUARE_SIZE) / 2.0;
    bool left = false;
    bool right = false;
    bool up = false;
    bool down = false;
    bool marker_visible = false;
    int marker_x = 0;
    int marker_y = 0;
    double previous = monotonic_seconds();

    printf("mover started at x=%.1f y=%.1f\n", x, y);

    for (;;) {
        while (XPending(display) > 0) {
            XEvent event;
            XNextEvent(display, &event);
            if (event.type == KeyPress || event.type == KeyRelease) {
                set_key_state(XLookupKeysym(&event.xkey, 0),
                              event.type == KeyPress, &left, &right, &up, &down);
            } else if (event.type == ButtonPress) {
                marker_visible = true;
                marker_x = event.xbutton.x;
                marker_y = event.xbutton.y;
                printf("mouse click at x=%d y=%d\n", marker_x, marker_y);
            }
        }

        double now = monotonic_seconds();
        double delta = now - previous;
        previous = now;
        const double speed = 180.0;
        x += ((right ? 1.0 : 0.0) - (left ? 1.0 : 0.0)) * speed * delta;
        y += ((down ? 1.0 : 0.0) - (up ? 1.0 : 0.0)) * speed * delta;

        if (x < 0.0) {
            x = 0.0;
        } else if (x > WINDOW_WIDTH - SQUARE_SIZE) {
            x = WINDOW_WIDTH - SQUARE_SIZE;
        }
        if (y < 0.0) {
            y = 0.0;
        } else if (y > WINDOW_HEIGHT - SQUARE_SIZE) {
            y = WINDOW_HEIGHT - SQUARE_SIZE;
        }

        XClearWindow(display, window);
        XSetForeground(display, gc, green.pixel);
        XFillRectangle(display, window, gc, (int)x, (int)y, SQUARE_SIZE,
                       SQUARE_SIZE);
        if (marker_visible) {
            XSetForeground(display, gc, red.pixel);
            XFillRectangle(display, window, gc, marker_x - 4, marker_y - 4, 9,
                           9);
        }
        XFlush(display);

        struct timespec frame = {.tv_sec = 0, .tv_nsec = 16000000};
        nanosleep(&frame, NULL);
    }
}
