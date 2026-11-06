#include "../runtime/nvn/vulkan/debug_capture_window.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
    assert(!vk_debug_frame_in_window(0, 0, 4));
    assert(!vk_debug_frame_in_window(479, 480, 4));
    assert(vk_debug_frame_in_window(480, 480, 4));
    assert(vk_debug_frame_in_window(481, 480, 4));
    assert(vk_debug_frame_in_window(482, 480, 4));
    assert(vk_debug_frame_in_window(483, 480, 4));
    assert(!vk_debug_frame_in_window(484, 480, 4));
    assert(!vk_debug_frame_in_window(UINT64_MAX, 480, 4));
    assert(!vk_debug_frame_in_window(480, 480, 0));
    assert(vk_debug_frame_in_window(UINT64_MAX, UINT64_MAX, 1));
    puts("F9 renderer-frame window tests passed");
    return 0;
}
