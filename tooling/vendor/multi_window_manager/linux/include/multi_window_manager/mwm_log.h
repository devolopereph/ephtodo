#ifndef MULTI_WINDOW_MANAGER_MWM_LOG_H_
#define MULTI_WINDOW_MANAGER_MWM_LOG_H_

#include <glib.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef MWM_LOG_DOMAIN
#define MWM_LOG_DOMAIN "mwm"
#endif

#ifdef MWM_LOG_ENABLED
#define MWM_LOG(fmt, ...)                                                    \
  g_log(MWM_LOG_DOMAIN, G_LOG_LEVEL_MESSAGE, "[%s:%d] " fmt, __func__,       \
        __LINE__, ##__VA_ARGS__)
#define MWM_LOG_ID(id, fmt, ...)                                             \
  g_log(MWM_LOG_DOMAIN, G_LOG_LEVEL_MESSAGE,                                 \
        "[%s:%d] windowId=%" G_GINT64_FORMAT " " fmt, __func__, __LINE__,    \
        (gint64)(id), ##__VA_ARGS__)
#else
#define MWM_LOG(fmt, ...)        do {} while (0)
#define MWM_LOG_ID(id, fmt, ...) do {} while (0)
#endif

#ifdef __cplusplus
}
#endif

#endif  // MULTI_WINDOW_MANAGER_MWM_LOG_H_
