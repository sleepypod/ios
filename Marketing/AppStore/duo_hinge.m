// Opens or closes the iPhone Duo simulator's hinge for marketing captures. simctl has no fold
// command, so capture.py builds this for the simulator SDK and runs it with `xcrun simctl spawn`.
// It posts the vendor-defined HID events Xcode's Device Hub sends for its hinge slider and its
// Rotate Left/Right controls; capture.py then checks which display is active with devicectl.
// Simulator only; private API, never linked into the app.
//
//   duo_hinge <degrees>              0 is closed (cover display), 180 is open flat (inner display)
//   duo_hinge orient <orientation>   portrait, landscape-left, landscape-right or pud
//
// Adapted from hinge by Artem Novichkov (https://github.com/artemnovichkov/hinge):
//
// MIT License
//
// Copyright (c) 2026 Artem Novichkov
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventRef IOHIDEventCreateVendorDefinedEvent(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t usagePage, uint32_t usage, uint32_t version, const uint8_t *data, CFIndex length, uint32_t options);
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, int type,
    CFDictionaryRef properties);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
extern CFDataRef IOCFSerialize(CFTypeRef object, CFOptionFlags options);

static void send_payload(IOHIDEventSystemClientRef client, CFStringRef source, CFStringRef type, CFTypeRef value) {
    const void *keys[] = {CFSTR("provider"), CFSTR("source"), CFSTR("type"), CFSTR("value")};
    const void *values[] = {CFSTR("com.apple.Virtualization.VirtualMachines"), source, type, value};
    CFDictionaryRef payload = CFDictionaryCreate(NULL, keys, values, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDataRef data = IOCFSerialize(payload, 1);
    if (data) {
        IOHIDEventRef event = IOHIDEventCreateVendorDefinedEvent(NULL, mach_absolute_time(), 0xFF61, 0x5B, 0,
            CFDataGetBytePtr(data), CFDataGetLength(data), 0);
        if (event) {
            IOHIDEventSystemClientDispatchEvent(client, event);
            CFRelease(event);
        }
        CFRelease(data);
    }
    CFRelease(payload);
}

int main(int argc, char **argv) {
    bool orient = argc == 3 && strcmp(argv[1], "orient") == 0;
    if (argc != 2 && !orient) {
        fprintf(stderr, "usage: duo_hinge <degrees 0-180>\n       duo_hinge orient <portrait|landscape-left|landscape-right|pud>\n");
        return 64;
    }
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateWithType(NULL, 4, NULL);
    if (!client) {
        fprintf(stderr, "duo_hinge: no HID event system client\n");
        return 1;
    }
    if (orient) {
        CFStringRef value = CFStringCreateWithCString(NULL, argv[2], kCFStringEncodingUTF8);
        send_payload(client, CFSTR("orientation-picker-control"), CFSTR("enum"), value);
        CFRelease(value);
    } else {
        double degrees = fmin(180, fmax(0, atof(argv[1])));
        CFNumberRef value = CFNumberCreate(NULL, kCFNumberDoubleType, &degrees);
        send_payload(client, CFSTR("hinge-slider-control"), CFSTR("range"), value);
        CFRelease(value);
    }
    usleep(20000);  // Let the event leave before the process exits.
    return 0;
}
