#ifndef FLUTTER_PLUGIN_MULTI_WINDOW_MANAGER_PLUGIN_H_
#define FLUTTER_PLUGIN_MULTI_WINDOW_MANAGER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <string>
#include <vector>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _MultiWindowManagerPlugin MultiWindowManagerPlugin;
typedef struct {
  GObjectClass parent_class;
} MultiWindowManagerPluginClass;

FLUTTER_PLUGIN_EXPORT GType multi_window_manager_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void multi_window_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

// Called by the plugin when Dart requests a new window (createWindow).
// The runner must create a new GtkWindow + FlView + Flutter engine using the
// provided Dart entrypoint arguments.
//
// The first argument will always be the windowId as a decimal string.
typedef void (*MultiWindowManagerPluginWindowCreatedCallback)(
    std::vector<std::string> dart_entrypoint_arguments);

FLUTTER_PLUGIN_EXPORT void MultiWindowManagerPluginSetWindowCreatedCallback(
    MultiWindowManagerPluginWindowCreatedCallback callback);

// Flutter's FlView (see engine fl_view.cc realize_cb) connects delete-event on
// the toplevel GtkWindow that calls fl_engine_request_app_exit(), which ends
// in g_application_quit() and terminates the whole GtkApplication - even when
// the user closes a secondary window. Each secondary window created with
// fl_view_new() must call this once after fl_register_plugins(), passing the
// same GtkWindow and FlView, so closing that window only destroys that window.
FLUTTER_PLUGIN_EXPORT void multi_window_manager_linux_detach_flutter_quit_on_window_close(
    GtkWindow* window,
    FlView* view);

// Function pointer type for the generated fl_register_plugins() function.
typedef void (*MwmRegisterPluginsFunc)(FlPluginRegistry* registry);

// Minimal setup for multi-window support inside my_application_activate.
// Call this once (before fl_register_plugins) when you want to keep the
// standard Flutter-generated activate body and just add MWM support:
//   - holds the application (prevents GTK auto-quit on secondary window close)
//   - installs the internal thread-safe window-creation callback so that
//     Dart's MultiWindowManager.createWindow() works
//
// After fl_register_plugins() also call:
//   multi_window_manager_linux_detach_flutter_quit_on_window_close(window, view)
//
// Pass fl_register_plugins (from flutter/generated_plugin_registrant.h) as
// the register_plugins argument so the library can register all plugins for
// every secondary window it creates on behalf of Dart.
FLUTTER_PLUGIN_EXPORT void multi_window_manager_linux_init(
    GtkApplication* app,
    MwmRegisterPluginsFunc register_plugins);

// All-in-one alternative to multi_window_manager_linux_init: replaces the
// entire activate body with a single call (creates the initial Flutter window
// internally using the same header-bar detection logic as the Flutter template).
FLUTTER_PLUGIN_EXPORT void multi_window_manager_linux_activate(
    GtkApplication* app,
    char** dart_args,
    MwmRegisterPluginsFunc register_plugins);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_MULTI_WINDOW_MANAGER_PLUGIN_H_
