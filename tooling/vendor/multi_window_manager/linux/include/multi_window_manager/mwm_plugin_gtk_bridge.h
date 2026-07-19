#ifndef MWM_PLUGIN_GTK_BRIDGE_H_
#define MWM_PLUGIN_GTK_BRIDGE_H_

#include <gtk/gtk.h>

#include <glib.h>

G_BEGIN_DECLS

/// Connects MultiWindowManager GTK signals for one toplevel [GtkWindow].
/// [plugin] is a #MultiWindowManagerPlugin*.
void mwm_plugin_bridge_connect_gtk_window_signals(GtkWindow* window,
                                                  gpointer plugin);

/// Disconnects all handlers that were connected with [plugin] as user_data.
void mwm_plugin_bridge_disconnect_gtk_window_signals(GtkWindow* window,
                                                     gpointer plugin);

G_END_DECLS

#endif
