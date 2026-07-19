#include <multi_window_manager/mwm_linux_classic_gl_survivor.h>

void mwm_linux_classic_gl_survivor_before_secondary_destroy(
    int64_t /*closing_id*/) {
  // No-op: secondary window close without reuseMode is not supported on Linux.
  // Forced reuseMode=true on Linux avoids the need for this recovery path.
}
