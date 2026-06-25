// dockswipe.m — synthesize macOS trackpad "dock-swipe" gestures
//
// Drives Mission Control / Spaces switching / App Exposé / Launchpad / Show-Desktop
// through the genuine trackpad GESTURE pathway (not a keyboard shortcut, not an
// instant space-switch API), with controllable speed (finger-following animation).
//
// The private CGEvent field layout is ported verbatim from Mac Mouse Fix:
//   Helper/Core/Touch/TouchSimulator.m  (+postDockSwipeEventWithDelta:type:phase:invertedFromDevice:)
//   — see TouchSimulator.reference.m in this repo. pre-macOS-27 ("field") path only.
//
// Build:  make            (or: clang -O2 -Wall -framework CoreGraphics -framework ApplicationServices -o dockswipe dockswipe.m)
// Perms:  grant the running terminal/binary Accessibility in System Settings > Privacy & Security.
//         No SIP disable, no special entitlement. Effect is system-global (Dock/WindowServer).
//
// ⚠️ Private/undocumented API. Works ~macOS 10.11–26 (Tahoe); macOS 27+ needs the IOHIDEvent path.
//    Not App-Store compatible. Intended for automated UI testing on machines you control.

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdbool.h>

// Baked in at compile time. Local builds default to 0.0.0-development; CI
// passes the real version via -DDOCKSWIPE_VERSION (see Makefile's VERSION).
#ifndef DOCKSWIPE_VERSION
#define DOCKSWIPE_VERSION "0.0.0-development"
#endif

// MFDockSwipeType (from TouchSimulator.h)
typedef enum { kAxisHorizontal = 1, kAxisVertical = 2, kAxisPinch = 3 } DockSwipeAxis;

// IOHIDEventPhaseBits subset
enum { kPhaseBegan = 1, kPhaseChanged = 2, kPhaseEnded = 4, kPhaseCancelled = 8 };

static const int kIOHIDEventTypeDockSwipe = 23;

// ---- runtime config (set from argv) -------------------------------------------------
static CGEventTapLocation gTap = kCGSessionEventTap;
static bool   gDryRun  = false;
static bool   gVerbose = false;

// ---- accumulating state, mirrors MMF's static _dockSwipeOriginOffset ----------------
static double gOriginOffset = 0.0;
static double gLastDelta     = 0.0;

static double weirdFloatForAxis(DockSwipeAxis a) {
    // IEEE-754 denormals whose raw 32-bit pattern == the integer axis value (1/2/3)
    if (a == kAxisHorizontal) return 1.401298464324817e-45;  // bits 0x1
    if (a == kAxisVertical)   return 2.802596928649634e-45;  // bits 0x2
    return 4.203895392974451e-45;                            // bits 0x3 (pinch)
}

static const char *axisName(DockSwipeAxis a) {
    return a == kAxisHorizontal ? "horizontal" : a == kAxisVertical ? "vertical" : "pinch";
}
static const char *phaseName(int p) {
    return p == kPhaseBegan ? "began" : p == kPhaseChanged ? "changed"
         : p == kPhaseEnded ? "ended" : "cancelled";
}

// Post ONE dock-swipe step. `d` sign chooses direction (up/down or left/right or in/out).
static void postDockSwipe(double d, DockSwipeAxis axis, int phase) {
    if (phase == kPhaseBegan)        gOriginOffset  = d;
    else if (phase == kPhaseChanged) { if (d == 0) return; gOriginOffset += d; }

    double exitSpeed = 0;
    if (phase == kPhaseEnded || phase == kPhaseCancelled) exitSpeed = gLastDelta * 100.0;

    // Reversed swipe → downgrade Ended to Cancelled (sign of last delta vs accumulated)
    if (phase == kPhaseEnded) {
        int sl = (gLastDelta > 0) - (gLastDelta < 0);
        int so = (gOriginOffset > 0) - (gOriginOffset < 0);
        if (sl != so) phase = kPhaseCancelled;
    }

    if (gVerbose || gDryRun) {
        fprintf(stderr, "[dockswipe] %-10s %-9s delta=%+.4f offset=%+.4f%s\n",
                axisName(axis), phaseName(phase), d, gOriginOffset,
                gDryRun ? "  (dry-run)" : "");
    }
    if (gDryRun) { gLastDelta = d; return; }

    const int valFor41 = 33231; // MMF author: 'might help'; likely omittable

    // e29: companion NSEventTypeGesture(29) marker
    CGEventRef e29 = CGEventCreate(NULL);
    CGEventSetDoubleValueField(e29, (CGEventField)55, 29);
    CGEventSetDoubleValueField(e29, (CGEventField)41, valFor41);

    // e30: main dock-control event (written as NSEventTypeMagnify==30 == kCGSEventDockControl)
    CGEventRef e30 = CGEventCreate(NULL);
    CGEventSetDoubleValueField(e30, (CGEventField)55, 30);
    CGEventSetDoubleValueField(e30, (CGEventField)110, kIOHIDEventTypeDockSwipe); // 23 = subtype
    CGEventSetDoubleValueField(e30, (CGEventField)132, phase);
    CGEventSetDoubleValueField(e30, (CGEventField)134, phase);                    // redundant phase

    // progress / amount (the speed-control value)
    CGEventSetDoubleValueField(e30, (CGEventField)124, gOriginOffset);
    Float32 ofsF = (Float32)gOriginOffset;
    uint32_t ofsU; memcpy(&ofsU, &ofsF, sizeof(ofsF));
    int64_t ofsI = (int64_t)ofsU;                                                // MUST go via uint32_t
    CGEventSetIntegerValueField(e30, (CGEventField)135, ofsI);
    CGEventSetDoubleValueField(e30, (CGEventField)41, valFor41);

    // axis / direction encoding (two redundant forms)
    double wf = weirdFloatForAxis(axis);
    CGEventSetDoubleValueField(e30, (CGEventField)119, wf);
    CGEventSetDoubleValueField(e30, (CGEventField)139, wf);                       // probably unnecessary
    CGEventSetDoubleValueField(e30, (CGEventField)123, (double)axis);             // primary axis selector
    CGEventSetDoubleValueField(e30, (CGEventField)165, (double)axis);             // redundant
    CGEventSetIntegerValueField(e30, (CGEventField)136, 0);                       // invertedFromDevice = NO

    if (phase == kPhaseEnded || phase == kPhaseCancelled) {
        CGEventSetDoubleValueField(e30, (CGEventField)129, exitSpeed);
        CGEventSetDoubleValueField(e30, (CGEventField)130, exitSpeed);
    }

    // dock swipe posts to the SESSION tap by default (MMF); --tap hid as fallback
    CGEventPost(gTap, e30);
    CGEventPost(gTap, e29);
    CFRelease(e29);
    CFRelease(e30);

    gLastDelta = d;
}

// Drive a full, speed-controlled gesture.
//   signedOffset : total accumulated offset; SIGN = direction (≈1.0–3.0 for a full screen)
//   steps        : animation granularity (frames)
//   usPerStep    : per-frame interval in microseconds (real trackpad ≈ 8000)
//   endResends   : extra Ended re-posts to mitigate the 'stuck gesture' bug
//   resendDelayUs: delay before each resend
static void doGesture(DockSwipeAxis axis, double signedOffset, int steps,
                      useconds_t usPerStep, int endResends, useconds_t resendDelayUs) {
    if (steps < 1) steps = 1;
    double step = signedOffset / steps;

    postDockSwipe(step, axis, kPhaseBegan);
    usleep(usPerStep);
    for (int i = 1; i < steps; i++) {
        postDockSwipe(step, axis, kPhaseChanged);
        usleep(usPerStep);
    }
    // Use the last step (not 0) so exitSpeed/sign stay consistent and the gesture commits.
    postDockSwipe(step, axis, kPhaseEnded);
    for (int r = 0; r < endResends; r++) {
        usleep(resendDelayUs);
        postDockSwipe(step, axis, kPhaseEnded);
    }
}

// ---- CLI ----------------------------------------------------------------------------

static void printVersion(void) { printf("dockswipe %s\n", DOCKSWIPE_VERSION); }

static void printHelp(const char *p) {
    printf(
"dockswipe %s — synthesize macOS trackpad dock-swipe gestures\n"
"\n"
"USAGE\n"
"  %s <preset> [options]\n"
"  %s --axis <axis> --direction <dir> [options]\n"
"\n"
"PRESETS  (shorthand for an axis + direction)\n"
"  mission-control   vertical   up      open Mission Control\n"
"  app-expose        vertical   down    App Exposé (windows of front app)\n"
"  space-left        horizontal left    switch to the desktop on the left\n"
"  space-right       horizontal right   switch to the desktop on the right\n"
"  show-desktop      pinch      out     spread to show desktop\n"
"  launchpad         pinch      in      pinch to open Launchpad\n"
"\n"
"GESTURE SHAPE\n"
"  --axis <vertical|horizontal|pinch>   override/define the axis\n"
"  --direction <up|down|left|right|in|out>   override/define the direction\n"
"  --offset <float>     total accumulated travel (default 1.5; ~1.0–3.0 = full screen)\n"
"  --steps <int>        number of animation frames (default 25; more = smoother)\n"
"  --interval <us>      microseconds between frames (default 8000 ≈ real trackpad)\n"
"  --duration <ms>      total gesture time; if set, overrides --interval\n"
"  --invert             flip the direction sign (compensate natural-scrolling)\n"
"\n"
"REPETITION\n"
"  --repeat <int>       repeat the whole gesture N times (default 1)\n"
"  --repeat-delay <ms>  pause between repeats (default 400)\n"
"\n"
"ROBUSTNESS / COMPAT\n"
"  --tap <session|hid>  event tap to post to (default session)\n"
"  --end-resends <int>  extra Ended re-posts to avoid a stuck gesture (default 1)\n"
"  --end-resend-delay <ms>  delay before each resend (default 200)\n"
"\n"
"DEBUG\n"
"  -n, --dry-run        print the event stream instead of posting it\n"
"  -v, --verbose        log each posted frame\n"
"  -h, --help           show this help\n"
"  -V, --version        print version\n"
"\n"
"SPEED\n"
"  Speed = total_offset / (steps * interval). Bigger per-frame step or shorter\n"
"  interval = faster; more steps + larger interval = slower, smoother. e.g.\n"
"    %s mission-control --steps 60 --interval 12000     # slow, silky\n"
"    %s space-right     --offset 2.0 --steps 12 --interval 4000  # fast\n"
"    %s mission-control --duration 500                  # ~0.5s total\n"
"\n"
"EXAMPLES\n"
"  %s mission-control\n"
"  %s app-expose --duration 300\n"
"  %s --axis horizontal --direction left --repeat 2 --repeat-delay 600\n"
"  %s space-right --dry-run -v\n"
"\n"
"NOTES\n"
"  • Direction sign depends on the 'natural scrolling' setting; use --invert if reversed.\n"
"  • Private API. macOS 10.11–26 only (field path). macOS 27+ needs the IOHIDEvent path.\n"
"  • Requires Accessibility permission. Effect is system-global (no target app needed).\n",
    DOCKSWIPE_VERSION, p, p, p, p, p, p, p, p, p);
}

// returns sign for a direction token, or 0 if invalid; sets *axisOut if the token implies an axis
static int dirSign(const char *d) {
    if (!strcmp(d, "up")    || !strcmp(d, "right") || !strcmp(d, "out")) return +1;
    if (!strcmp(d, "down")  || !strcmp(d, "left")  || !strcmp(d, "in"))  return -1;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { printHelp(argv[0]); return 2; }

    DockSwipeAxis axis = kAxisVertical; bool axisSet = false;
    int  sign = +1;                     bool signSet = false;
    bool invert = false;
    double offset = 1.5;
    int    steps = 25;
    long   intervalUs = 8000;
    long   durationMs = -1;             // if >=0, overrides interval
    int    repeat = 1;
    long   repeatDelayMs = 400;
    int    endResends = 1;
    long   endResendDelayMs = 200;

    int i = 1;

    // optional leading preset (token not starting with '-')
    if (argv[1][0] != '-') {
        const char *g = argv[1];
        if      (!strcmp(g, "mission-control")) { axis = kAxisVertical;   sign = +1; }
        else if (!strcmp(g, "app-expose"))      { axis = kAxisVertical;   sign = -1; }
        else if (!strcmp(g, "space-left"))      { axis = kAxisHorizontal; sign = -1; }
        else if (!strcmp(g, "space-right"))     { axis = kAxisHorizontal; sign = +1; }
        else if (!strcmp(g, "show-desktop"))    { axis = kAxisPinch;      sign = +1; }
        else if (!strcmp(g, "launchpad"))       { axis = kAxisPinch;      sign = -1; }
        else { fprintf(stderr, "dockswipe: unknown preset '%s'\n", g); return 2; }
        axisSet = signSet = true;
        i = 2;
    }

    for (; i < argc; i++) {
        const char *a = argv[i];
        #define NEED_VAL() (i + 1 < argc ? argv[++i] : (fprintf(stderr, "dockswipe: %s needs a value\n", a), exit(2), ""))
        if      (!strcmp(a, "-h") || !strcmp(a, "--help"))    { printHelp(argv[0]); return 0; }
        else if (!strcmp(a, "-V") || !strcmp(a, "--version")) { printVersion();     return 0; }
        else if (!strcmp(a, "-n") || !strcmp(a, "--dry-run")) gDryRun = true;
        else if (!strcmp(a, "-v") || !strcmp(a, "--verbose")) gVerbose = true;
        else if (!strcmp(a, "--invert")) invert = true;
        else if (!strcmp(a, "--axis")) {
            const char *v = NEED_VAL();
            if      (!strcmp(v, "vertical"))   axis = kAxisVertical;
            else if (!strcmp(v, "horizontal")) axis = kAxisHorizontal;
            else if (!strcmp(v, "pinch"))      axis = kAxisPinch;
            else { fprintf(stderr, "dockswipe: bad --axis '%s'\n", v); return 2; }
            axisSet = true;
        }
        else if (!strcmp(a, "--direction")) {
            const char *v = NEED_VAL();
            int s = dirSign(v);
            if (s == 0) { fprintf(stderr, "dockswipe: bad --direction '%s'\n", v); return 2; }
            sign = s; signSet = true;
        }
        else if (!strcmp(a, "--offset"))           offset = atof(NEED_VAL());
        else if (!strcmp(a, "--steps"))            steps = atoi(NEED_VAL());
        else if (!strcmp(a, "--interval"))         intervalUs = atol(NEED_VAL());
        else if (!strcmp(a, "--duration"))         durationMs = atol(NEED_VAL());
        else if (!strcmp(a, "--repeat"))           repeat = atoi(NEED_VAL());
        else if (!strcmp(a, "--repeat-delay"))     repeatDelayMs = atol(NEED_VAL());
        else if (!strcmp(a, "--end-resends"))      endResends = atoi(NEED_VAL());
        else if (!strcmp(a, "--end-resend-delay")) endResendDelayMs = atol(NEED_VAL());
        else if (!strcmp(a, "--tap")) {
            const char *v = NEED_VAL();
            if      (!strcmp(v, "session")) gTap = kCGSessionEventTap;
            else if (!strcmp(v, "hid"))     gTap = kCGHIDEventTap;
            else { fprintf(stderr, "dockswipe: bad --tap '%s'\n", v); return 2; }
        }
        else { fprintf(stderr, "dockswipe: unknown option '%s' (try --help)\n", a); return 2; }
        #undef NEED_VAL
    }

    if (!axisSet) { fprintf(stderr, "dockswipe: specify a preset or --axis (try --help)\n"); return 2; }
    if (steps < 1) steps = 1;
    if (repeat < 1) repeat = 1;

    if (durationMs >= 0) intervalUs = (long)((durationMs * 1000.0) / steps);

    int finalSign = sign * (invert ? -1 : 1);
    double signedOffset = fabs(offset) * finalSign;

    for (int r = 0; r < repeat; r++) {
        doGesture(axis, signedOffset, steps, (useconds_t)intervalUs,
                  endResends, (useconds_t)(endResendDelayMs * 1000));
        if (r + 1 < repeat) usleep((useconds_t)(repeatDelayMs * 1000));
    }
    return 0;
}
