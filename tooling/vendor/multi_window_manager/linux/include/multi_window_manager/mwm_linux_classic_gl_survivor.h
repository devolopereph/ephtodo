#ifndef MWM_LINUX_CLASSIC_GL_SURVIVOR_H_
#define MWM_LINUX_CLASSIC_GL_SURVIVOR_H_

#include <cstdint>

// When a secondary GTK window (its own FlEngine) is destroyed, refresh another
// FlView's GL state so remaining windows keep rendering.
void mwm_linux_classic_gl_survivor_before_secondary_destroy(int64_t closing_window_id);

#endif
