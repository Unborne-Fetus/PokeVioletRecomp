// Rendering-frame capture membership, independent of the asynchronous queue.
#ifndef VIOLET_DEBUG_CAPTURE_WINDOW_H
#define VIOLET_DEBUG_CAPTURE_WINDOW_H
#include <stdbool.h>
#include <stdint.h>
static inline bool vk_debug_frame_in_window(uint64_t frame, uint64_t start, uint32_t count) {
    return start != 0 && count != 0 && frame >= start && frame - start < count;
}
#endif
