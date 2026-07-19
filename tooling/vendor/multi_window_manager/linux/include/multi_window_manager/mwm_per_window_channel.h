#ifndef MWM_PER_WINDOW_CHANNEL_H_
#define MWM_PER_WINDOW_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

void mwm_per_window_method_call_cb(FlMethodChannel* channel,
                                   FlMethodCall* method_call,
                                   gpointer user_data);

G_END_DECLS

#endif
