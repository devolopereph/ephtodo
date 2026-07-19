#include "multi_window_manager.h"

#include "include/multi_window_manager/mwm_log.h"

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <utility>

// ---- Static member definitions ----

std::mutex LinuxWindowManager::registry_mtx;
int64_t LinuxWindowManager::autoincrement_id = 0;
std::map<int64_t, std::shared_ptr<LinuxWindowManager>> LinuxWindowManager::windows;
MultiWindowManagerPluginWindowCreatedCallback
    LinuxWindowManager::window_created_callback = nullptr;

// ---- X11 docking helpers (file-local) ----

namespace {

FlView* fl_view_child_of_gtk_window(GtkWindow* window) {
  if (!window) return nullptr;
  GtkWidget* child = gtk_bin_get_child(GTK_BIN(window));
  if (!child || !FL_IS_VIEW(child)) return nullptr;
  return FL_VIEW(child);
}

GtkWidget* find_event_box_deep(GtkWidget* widget) {
  if (!widget) return nullptr;
  if (GTK_IS_EVENT_BOX(widget)) return widget;
  if (!GTK_IS_CONTAINER(widget)) return nullptr;
  GtkWidget* found = nullptr;
  GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
  for (GList* node = children; node && !found; node = node->next) {
    found = find_event_box_deep(GTK_WIDGET(node->data));
  }
  g_list_free(children);
  return found;
}

GtkWidget* flutter_input_target_of(GtkWindow* window) {
  FlView* view = fl_view_child_of_gtk_window(window);
  if (!view) return nullptr;
  GtkWidget* root = GTK_WIDGET(view);
  GtkWidget* event_box = find_event_box_deep(root);
  return event_box ? event_box : root;
}

#ifdef GDK_WINDOWING_X11
bool is_x11_window(GdkWindow* w) { return w && GDK_IS_X11_WINDOW(w); }

void x11_set_window_type_dock(Display* dpy, Window xid) {
  Atom prop = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
  Atom type_dock = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
  XChangeProperty(dpy, xid, prop, XA_ATOM, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&type_dock), 1);
}

void x11_clear_window_type(Display* dpy, Window xid) {
  Atom prop = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
  XDeleteProperty(dpy, xid, prop);
}

void x11_set_strut_partial(Display* dpy, Window xid, long left, long right,
                           long top, long bottom, long left_start_y,
                           long left_end_y, long right_start_y,
                           long right_end_y, long top_start_x, long top_end_x,
                           long bottom_start_x, long bottom_end_x) {
  Atom prop = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
  long data[12] = {left,         right,        top,          bottom,
                   left_start_y, left_end_y,   right_start_y, right_end_y,
                   top_start_x,  top_end_x,    bottom_start_x, bottom_end_x};
  XChangeProperty(dpy, xid, prop, XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(data), 12);

  Atom prop2 = XInternAtom(dpy, "_NET_WM_STRUT", False);
  long data2[4] = {left, right, top, bottom};
  XChangeProperty(dpy, xid, prop2, XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(data2), 4);
}

void x11_clear_strut(Display* dpy, Window xid) {
  Atom prop = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
  Atom prop2 = XInternAtom(dpy, "_NET_WM_STRUT", False);
  XDeleteProperty(dpy, xid, prop);
  XDeleteProperty(dpy, xid, prop2);
}
#endif
}  // namespace

// ---- Constructor / Destructor ----

LinuxWindowManager::LinuxWindowManager() {
  MWM_LOG_ID(id, "LinuxWindowManager()");
  geometry.min_width = -1;
  geometry.min_height = -1;
  geometry.max_width = G_MAXINT;
  geometry.max_height = G_MAXINT;
}

LinuxWindowManager::~LinuxWindowManager() {
  MWM_LOG_ID(id, "~LinuxWindowManager");
  StopDragReleaseWatcher();
  if (channel) g_object_unref(channel);
  if (css_provider) g_object_unref(css_provider);
  if (title_bar_style) g_free(title_bar_style);
}

// ---- Utility ----

GdkWindow* LinuxWindowManager::GetGdkWindow(GtkWindow* w) {
  if (!w) return nullptr;
  return gtk_widget_get_window(GTK_WIDGET(w));
}

GtkWidget* LinuxWindowManager::HeaderBarOf(GtkWindow* w) {
  GtkWidget* titlebar = gtk_window_get_titlebar(w);
  if (titlebar &&
      (GTK_IS_HEADER_BAR(titlebar) ||
       g_str_has_suffix(G_OBJECT_TYPE_NAME(titlebar), "HeaderBar"))) {
    return titlebar;
  }
  return nullptr;
}

FlValue* LinuxWindowManager::MakeBounds(GtkWindow* w) {
  gint x, y, width, height;
  gtk_window_get_position(w, &x, &y);
  gtk_window_get_size(w, &width, &height);
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  fl_value_set_string_take(map, "width", fl_value_new_float(width));
  fl_value_set_string_take(map, "height", fl_value_new_float(height));
  return map;
}

// ---- Event helpers ----

void LinuxWindowManager::EmitLocal(
    const std::shared_ptr<LinuxWindowManager>& wm, const char* event_name) {
  if (!wm || !wm->channel) return;
  MWM_LOG_ID(wm->id, "EmitLocal event=%s", event_name);
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "eventName", fl_value_new_string(event_name));
  fl_method_channel_invoke_method(wm->channel, "onEvent", map, nullptr,
                                  nullptr, nullptr);
}

void LinuxWindowManager::EmitGlobal(int64_t from_id, const char* event_name) {
  std::lock_guard<std::mutex> lock(registry_mtx);
  for (auto& pair : windows) {
    auto& wm = pair.second;
    if (!wm || !wm->channel) continue;
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "eventName",
                             fl_value_new_string(event_name));
    fl_value_set_string_take(
        map, "windowId", fl_value_new_int(static_cast<int64_t>(from_id)));
    fl_method_channel_invoke_method(wm->channel, "onEvent", map, nullptr,
                                    nullptr, nullptr);
  }
}

// ---- Registry helpers ----

std::shared_ptr<LinuxWindowManager> LinuxWindowManager::GetTarget(
    int64_t fallback_id, FlValue* args) {
  int64_t target_id = fallback_id;
  if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* w = fl_value_lookup_string(args, "windowId");
    if (w && fl_value_get_type(w) == FL_VALUE_TYPE_INT)
      target_id = fl_value_get_int(w);
  }
  std::lock_guard<std::mutex> lock(registry_mtx);
  auto it = windows.find(target_id);
  auto out = it == windows.end() ? nullptr : it->second;
  return out;
}

int64_t LinuxWindowManager::CreateWindow(
    const std::vector<std::string>& user_args) {
  MWM_LOG("CreateWindow user_arg_count=%zu callback=%p", user_args.size(),
          reinterpret_cast<void*>(window_created_callback));
  if (!window_created_callback) return -1;

  int64_t new_id;
  {
    std::lock_guard<std::mutex> lock(registry_mtx);
    autoincrement_id++;
    new_id = autoincrement_id;
  }

  std::vector<std::string> argv;
  argv.emplace_back(std::to_string(new_id));
  argv.insert(argv.end(), user_args.begin(), user_args.end());
  window_created_callback(std::move(argv));

  return new_id;
}

void LinuxWindowManager::Unregister(int64_t id) {
  MWM_LOG_ID(id, "Unregister");
  std::lock_guard<std::mutex> lock(registry_mtx);
  windows.erase(id);
}

void LinuxWindowManager::ForceDestroyAllWindowsExcept(int64_t keep_id) {
  std::vector<int64_t> ids;
  {
    std::lock_guard<std::mutex> lock(registry_mtx);
    for (const auto& pair : windows) {
      if (pair.first != keep_id) {
        ids.push_back(pair.first);
      }
    }
  }
  for (const int64_t id : ids) {
    std::shared_ptr<LinuxWindowManager> wm;
    {
      std::lock_guard<std::mutex> lock(registry_mtx);
      auto it = windows.find(id);
      if (it != windows.end()) {
        wm = it->second;
      }
    }
    if (!wm || !wm->window) {
      continue;
    }
    MWM_LOG_ID(id, "ForceDestroyAllWindowsExcept: destroying gtk window %p",
               static_cast<void*>(wm->window));
    wm->is_reuse_enabled = false;
    wm->is_in_reuse_pool = false;
    wm->is_being_reused = false;
    wm->is_confirm_close = true;
    wm->is_prevent_close = false;
    gtk_widget_destroy(GTK_WIDGET(wm->window));
  }
}

// ---- Window operations ----

void LinuxWindowManager::SetAsFrameless() {
  MWM_LOG_ID(id, "SetAsFrameless");
  if (window) gtk_window_set_decorated(window, false);
}

void LinuxWindowManager::Close() {
  MWM_LOG_ID(id, "Close (schedule idle) window=%p",
             static_cast<void*>(window));
  if (!window) return;
  // Deferred close (like Windows PostMessage) to avoid re-entrant destruction
  // when called from a method channel handler on this engine.
  auto* wid = new int64_t(id);
  g_idle_add(
      [](gpointer data) -> gboolean {
        std::unique_ptr<int64_t> p(static_cast<int64_t*>(data));
        MWM_LOG_ID(*p, "Close idle: gtk_window_close");
        auto wm = LinuxWindowManager::GetTarget(*p, nullptr);
        if (wm && wm->window) gtk_window_close(wm->window);
        else
          MWM_LOG_ID(*p, "Close idle: wm or window gone (already destroyed?)");
        return G_SOURCE_REMOVE;
      },
      wid);
}

void LinuxWindowManager::Destroy() {
  MWM_LOG_ID(id, "Destroy");
  if (!window) return;
  is_prevent_close = false;
  is_confirm_close = true;
  is_reuse_enabled = false;
  Close();
}

void LinuxWindowManager::RestoreFlutterViewFocus() {
  if (!window) return;
  gtk_window_present(window);
  GtkWidget* input = flutter_input_target_of(window);
  if (input && gtk_widget_get_realized(input)) {
    gtk_widget_grab_focus(input);
  }
}

void LinuxWindowManager::EmitSyntheticPointerRelease() {
  if (!window) return;
  GtkWidget* input = flutter_input_target_of(window);
  if (!input) return;

  // Do not set GdkEventButton::window - gdk_event_free() would unref it and can
  // destroy the FlView GdkWindow (crash on the next drag). window_manager omits it.
  GdkEvent* event = gdk_event_new(GDK_BUTTON_RELEASE);
  auto* btn = reinterpret_cast<GdkEventButton*>(event);
  btn->button = last_button.button ? last_button.button : GDK_BUTTON_PRIMARY;
  btn->time = last_button.time ? last_button.time : (guint32)g_get_monotonic_time();
  btn->x = last_button.x;
  btn->y = last_button.y;

  gboolean handled = FALSE;
  g_signal_emit_by_name(input, "button-release-event", btn, &handled);
  gdk_event_free(event);
}

bool LinuxWindowManager::IsPointerButtonStillPressed() const {
  if (!window) return false;
  auto* screen = gtk_window_get_screen(window);
  auto* display = gdk_screen_get_display(screen);
  auto* seat = gdk_display_get_default_seat(display);
  auto* device = gdk_seat_get_pointer(seat);
  GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
  if (!gdk || !device) return false;

  gint x = 0;
  gint y = 0;
  GdkModifierType state = static_cast<GdkModifierType>(0);
  gdk_window_get_device_position(gdk, device, &x, &y, &state);
  const guint pressed_button =
      last_button.button ? last_button.button : GDK_BUTTON_PRIMARY;
  GdkModifierType button_mask = GDK_BUTTON1_MASK;
  if (pressed_button == 2) {
    button_mask = GDK_BUTTON2_MASK;
  } else if (pressed_button == 3) {
    button_mask = GDK_BUTTON3_MASK;
  }
  return (state & button_mask) != 0;
}

void LinuxWindowManager::StopDragReleaseWatcher() {
  if (drag_release_watch_id == 0) return;
  const guint tag = drag_release_watch_id;
  drag_release_watch_id = 0;
  g_source_remove(tag);
}

void LinuxWindowManager::FinishInteractiveWindowGesture() {
  if (!is_dragging && !is_resizing) return;
  if (IsPointerButtonStillPressed()) return;

  MWM_LOG_ID(id, "FinishInteractiveWindowGesture drag=%d resize=%d",
             is_dragging, is_resizing);
  is_dragging = false;
  is_resizing = false;
  EmitSyntheticPointerRelease();
  RestoreFlutterViewFocus();
}

gboolean LinuxWindowManager::DragReleaseWatchCb(gpointer data) {
  auto* self = static_cast<LinuxWindowManager*>(data);
  std::shared_ptr<LinuxWindowManager> keep;
  {
    std::lock_guard<std::mutex> lock(registry_mtx);
    auto it = windows.find(self->id);
    if (it == windows.end()) {
      self->drag_release_watch_id = 0;
      return G_SOURCE_REMOVE;
    }
    keep = it->second;
  }
  if (!self->is_dragging && !self->is_resizing) {
    self->drag_release_watch_id = 0;
    return G_SOURCE_REMOVE;
  }
  if (!self->window) {
    self->drag_release_watch_id = 0;
    return G_SOURCE_REMOVE;
  }

  if (self->IsPointerButtonStillPressed()) {
    return G_SOURCE_CONTINUE;
  }

  self->FinishInteractiveWindowGesture();
  self->drag_release_watch_id = 0;
  return G_SOURCE_REMOVE;
}

void LinuxWindowManager::EnsureDragReleaseWatcher() {
  StopDragReleaseWatcher();
  drag_release_watch_id = g_idle_add(DragReleaseWatchCb, this);
}

void LinuxWindowManager::Focus() {
  if (!window) return;
  if (is_reuse_enabled && is_in_reuse_pool) return;
  RestoreFlutterViewFocus();
}

bool LinuxWindowManager::IsFocused() {
  return window ? gtk_window_is_active(window) : false;
}

void LinuxWindowManager::Show() {
  if (!window) return;
  if (is_reuse_enabled && is_in_reuse_pool && !is_being_reused) return;
  if (is_reuse_enabled && is_in_reuse_pool) is_in_reuse_pool = false;
  is_being_reused = false;

  // Apply any pending position before mapping so the WM receives the desired
  // coordinates alongside the MapRequest (X11 PPosition hint).
  ApplyPendingMove();
  gtk_widget_show(GTK_WIDGET(window));
  gtk_window_present(window);
}

void LinuxWindowManager::ApplyPendingMove() {
  if (!window || !has_pending_move) return;
  has_pending_move = false;
  gtk_window_move(window, pending_move_x, pending_move_y);
}

void LinuxWindowManager::Hide() {
  if (!window) return;
  gint x, y, w, h;
  gtk_window_get_position(window, &x, &y);
  gtk_window_get_size(window, &w, &h);
  gtk_widget_hide(GTK_WIDGET(window));
  gtk_window_move(window, x, y);
  gtk_window_resize(window, w, h);
}

bool LinuxWindowManager::IsVisible() {
  return window ? gtk_widget_is_visible(GTK_WIDGET(window)) : false;
}

bool LinuxWindowManager::IsMaximized() {
  return window ? gtk_window_is_maximized(window) : false;
}

void LinuxWindowManager::Maximize() {
  if (!window || !is_maximizable) return;
  gtk_window_maximize(window);
}

void LinuxWindowManager::Unmaximize() {
  if (window) gtk_window_unmaximize(window);
}

bool LinuxWindowManager::IsMinimized() {
  if (!window) return false;
  auto* gdk = GetGdkWindow(window);
  return gdk
             ? (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_ICONIFIED) != 0
             : false;
}

void LinuxWindowManager::Minimize() {
  if (!window || !is_minimizable) return;
  gtk_window_iconify(window);
}

void LinuxWindowManager::Restore() {
  if (!window) return;
  gtk_window_deiconify(window);
  gtk_window_present(window);
}

bool LinuxWindowManager::IsDockable() {
  MWM_LOG_ID(id, "IsDockable");
#ifdef GDK_WINDOWING_X11
  return window && is_x11_window(GetGdkWindow(window));
#else
  return false;
#endif
}

int LinuxWindowManager::IsDocked() {
  MWM_LOG_ID(id, "IsDocked -> %d", dock_state);
  return dock_state;
}

bool LinuxWindowManager::Dock(bool left, bool right, int width) {
  MWM_LOG_ID(id, "Dock left=%d right=%d width=%d", left, right, width);
#ifdef GDK_WINDOWING_X11
  if (!window) return false;
  GdkWindow* gw = GetGdkWindow(window);
  if (!is_x11_window(gw)) return false;

  GdkDisplay* gdk_display = gdk_window_get_display(gw);
  Display* dpy = gdk_x11_display_get_xdisplay(gdk_display);
  const Window xid = gdk_x11_window_get_xid(gw);

  GdkMonitor* monitor = gdk_display_get_monitor_at_window(gdk_display, gw);
  GdkRectangle geo{};
  if (monitor) {
    gdk_monitor_get_geometry(monitor, &geo);
  } else {
    GdkMonitor* primary = gdk_display_get_primary_monitor(gdk_display);
    if (primary) {
      gdk_monitor_get_geometry(primary, &geo);
    } else {
      int wx, wy, ww, wh;
      gdk_window_get_geometry(gw, &wx, &wy, &ww, &wh);
      geo.width = ww;
      geo.height = wh;
    }
  }

  x11_set_window_type_dock(dpy, xid);

  const long l = (left && !right) ? width : 0;
  const long r = (right && !left) ? width : 0;
  const long start_y = geo.y;
  const long end_y = geo.y + geo.height - 1;

  x11_set_strut_partial(dpy, xid, l, r, 0, 0, start_y, end_y, start_y, end_y,
                        0, 0, 0, 0);
  XFlush(dpy);

  if (left && !right) {
    gtk_window_move(window, geo.x, geo.y);
    gtk_window_resize(window, width, geo.height);
    dock_state = 1;
  } else if (right && !left) {
    gtk_window_move(window, geo.x + geo.width - width, geo.y);
    gtk_window_resize(window, width, geo.height);
    dock_state = 2;
  } else {
    dock_state = 0;
  }
  return dock_state != 0;
#else
  return false;
#endif
}

bool LinuxWindowManager::Undock() {
  MWM_LOG_ID(id, "Undock");
#ifdef GDK_WINDOWING_X11
  if (!window) return false;
  GdkWindow* gw = GetGdkWindow(window);
  if (!is_x11_window(gw)) return false;

  GdkDisplay* gdk_display = gdk_window_get_display(gw);
  Display* dpy = gdk_x11_display_get_xdisplay(gdk_display);
  const Window xid = gdk_x11_window_get_xid(gw);
  x11_clear_strut(dpy, xid);
  x11_clear_window_type(dpy, xid);
  XFlush(dpy);
  dock_state = 0;
  return true;
#else
  return false;
#endif
}

bool LinuxWindowManager::IsFullScreen() {
  MWM_LOG_ID(id, "IsFullScreen");
  if (!window) return false;
  auto* gdk = GetGdkWindow(window);
  return gdk
             ? (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_FULLSCREEN) != 0
             : false;
}

void LinuxWindowManager::SetFullScreen(bool fs) {
  MWM_LOG_ID(id, "SetFullScreen fs=%d", fs);
  if (!window) return;
  if (fs)
    gtk_window_fullscreen(window);
  else
    gtk_window_unfullscreen(window);
}

namespace {

constexpr gint kAspectMinDim = 64;

// Returns false if [width]x[height] already match [aspect] (within tolerance).
bool SizeForAspectRatio(gint width,
                        gint height,
                        float aspect,
                        gint min_w,
                        gint min_h,
                        gint* out_width,
                        gint* out_height) {
  if (aspect <= 0.0f || width < min_w || height < min_h) {
    return false;
  }
  const double current = static_cast<double>(width) / height;
  if (std::fabs(current - aspect) < 0.01) {
    return false;
  }
  gint w = width;
  gint h = height;
  if (current > aspect) {
    h = static_cast<gint>(width / aspect + 0.5);
  } else {
    w = static_cast<gint>(height * aspect + 0.5);
  }
  w = std::max(w, min_w);
  h = std::max(h, min_h);
  if (w == width && h == height) {
    return false;
  }
  *out_width = w;
  *out_height = h;
  return true;
}

}  // namespace

void LinuxWindowManager::ClearGdkAspectHints() {
  hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_ASPECT);
  geometry.min_aspect = 1;
  geometry.max_aspect = G_MAXINT;
  if (auto* gdk = GetGdkWindow(window)) {
    gdk_window_set_geometry_hints(gdk, &geometry, hints);
  }
}

void LinuxWindowManager::SetAspectRatio(float ar) {
  MWM_LOG_ID(id, "SetAspectRatio ar=%f", ar);
  if (!window) return;

  aspect_ratio = ar > 0.0f ? ar : 0.0f;

  // GDK_HINT_ASPECT breaks gtk_window_begin_resize_drag on frameless windows
  // (height collapses to ~1px and cannot be restored). Only apply size once here.
  ClearGdkAspectHints();

  if (aspect_ratio <= 0.0f) {
    return;
  }

  gint width = 0;
  gint height = 0;
  gtk_window_get_size(window, &width, &height);

  const gint min_w = (hints & GDK_HINT_MIN_SIZE) && geometry.min_width > 0
                         ? geometry.min_width
                         : kAspectMinDim;
  const gint min_h = (hints & GDK_HINT_MIN_SIZE) && geometry.min_height > 0
                         ? geometry.min_height
                         : kAspectMinDim;

  gint new_width = width;
  gint new_height = height;
  if (!SizeForAspectRatio(width, height, aspect_ratio, min_w, min_h, &new_width,
                          &new_height)) {
    return;
  }

  MWM_LOG_ID(id, "SetAspectRatio resize %dx%d -> %dx%d", width, height, new_width,
             new_height);
  gtk_window_resize(window, new_width, new_height);
}

bool LinuxWindowManager::SetBackgroundColor(int r, int g, int b, int a) {
  MWM_LOG_ID(id, "SetBackgroundColor rgba=%d,%d,%d,%d", r, g, b, a);
  if (!window) return false;
  GdkRGBA rgba;
  rgba.red = r / 255.0;
  rgba.green = g / 255.0;
  rgba.blue = b / 255.0;
  rgba.alpha = a / 255.0;
  g_autofree gchar* color = gdk_rgba_to_string(&rgba);
  g_autofree gchar* css =
      g_strdup_printf("window { background-color: %s; }", color);
  // Keep app_paintable=true whenever the titlebar is hidden (to suppress CSD
  // shadow margins), regardless of background alpha.
  const bool titlebar_hidden =
      title_bar_style && g_strcmp0(title_bar_style, "hidden") == 0;
  gtk_widget_set_app_paintable(GTK_WIDGET(window), a < 255 || titlebar_hidden);
  if (!css_provider) {
    css_provider = gtk_css_provider_new();
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(GTK_WIDGET(window)),
        GTK_STYLE_PROVIDER(css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }
  g_autoptr(GError) error = nullptr;
  gtk_css_provider_load_from_data(css_provider, css, -1, &error);
  if (error != nullptr) {
    return false;
  }
  if (FlView* view = fl_view_child_of_gtk_window(window)) {
    fl_view_set_background_color(view, &rgba);
  }
  return true;
}

FlValue* LinuxWindowManager::GetBounds() {
  if (!window) return nullptr;
  return MakeBounds(window);
}

void LinuxWindowManager::SetBounds(FlValue* args) {
  if (!window || !args) return;
  FlValue* x = fl_value_lookup_string(args, "x");
  FlValue* y = fl_value_lookup_string(args, "y");
  if (x && y) {
    pending_move_x = static_cast<gint>(fl_value_get_float(x));
    pending_move_y = static_cast<gint>(fl_value_get_float(y));
    has_pending_move = true;
    if (gtk_widget_get_visible(GTK_WIDGET(window))) {
      ApplyPendingMove();
    }
    // If hidden: has_pending_move stays true; Show() calls ApplyPendingMove()
    // before gtk_widget_show() so the WM receives coordinates at map time.
  }
  FlValue* w = fl_value_lookup_string(args, "width");
  FlValue* h = fl_value_lookup_string(args, "height");
  if (w && h) {
    const gint target_w = (gint)fl_value_get_float(w);
    const gint target_h = (gint)fl_value_get_float(h);
    // gtk_window_resize works correctly for both visible and hidden windows
    // because SetTitleBarStyle zeroes the GDK shadow extents (via
    // gdk_window_set_shadow_width), so resize always addresses the content
    // area without any CSD-shadow offset.
    gtk_window_resize(window, target_w, target_h);
  }
}

void LinuxWindowManager::SetMinimumSize(float w, float h) {
  MWM_LOG_ID(id, "SetMinimumSize w=%f h=%f", w, h);
  if (!window) return;
  if (w >= 0 && h >= 0) {
    geometry.min_width = (gint)w;
    geometry.min_height = (gint)h;
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_MIN_SIZE);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_MIN_SIZE);
  }
  auto* gdk = GetGdkWindow(window);
  if (gdk) gdk_window_set_geometry_hints(gdk, &geometry, hints);
}

void LinuxWindowManager::SetMaximumSize(float w, float h) {
  MWM_LOG_ID(id, "SetMaximumSize w=%f h=%f", w, h);
  if (!window) return;
  geometry.max_width = (gint)w;
  geometry.max_height = (gint)h;
  if (w >= 0 && h >= 0) {
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_MAX_SIZE);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_MAX_SIZE);
  }
  if (geometry.max_width < 0) geometry.max_width = G_MAXINT;
  if (geometry.max_height < 0) geometry.max_height = G_MAXINT;
  auto* gdk = GetGdkWindow(window);
  if (gdk) gdk_window_set_geometry_hints(gdk, &geometry, hints);
}

bool LinuxWindowManager::IsResizable() {
  MWM_LOG_ID(id, "IsResizable");
  return window ? gtk_window_get_resizable(window) : false;
}

void LinuxWindowManager::SetResizable(bool v) {
  MWM_LOG_ID(id, "SetResizable v=%d", v);
  if (!window) return;
  if (!v) {
    // GTK3 uses gtk_window_set_default_size as the preferred/natural size for
    // non-resizable windows (gtk_window_resize is silently ignored when
    // resizable==false). Sync the default size to the current window size BEFORE
    // calling set_resizable so GTK pins to the right size, not the 1280x720
    // passed at window creation time.
    gint w = 0, h = 0;
    gtk_window_get_size(window, &w, &h);
    if (w > 0 && h > 0) gtk_window_set_default_size(window, w, h);
  }
  gtk_window_set_resizable(window, v);
  ApplyWmFunctions();
}

bool LinuxWindowManager::IsMinimizable() {
  return is_minimizable;
}

void LinuxWindowManager::SetMinimizable(bool v) {
  MWM_LOG_ID(id, "SetMinimizable v=%d", v);
  is_minimizable = v;
  ApplyWmFunctions();
}

bool LinuxWindowManager::IsMaximizable() {
  return is_maximizable;
}

void LinuxWindowManager::SetMaximizable(bool v) {
  MWM_LOG_ID(id, "SetMaximizable v=%d", v);
  is_maximizable = v;
  ApplyWmFunctions();
}

bool LinuxWindowManager::IsClosable() {
  return is_closable;
}

void LinuxWindowManager::SetClosable(bool v) {
  MWM_LOG_ID(id, "SetClosable v=%d", v);
  is_closable = v;
  if (!window) return;
  // gtk_window_set_deletable controls the WM close button hint on X11.
  gtk_window_set_deletable(window, v);
  GtkWidget* header = HeaderBarOf(window);
  if (header && GTK_IS_HEADER_BAR(header)) {
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), v);
  }
  ApplyWmFunctions();
}

void LinuxWindowManager::ApplyWmFunctions() {
  if (!window) return;
  GdkWindow* gdk_win = GetGdkWindow(window);
  if (!gdk_win) return;
  // Build the allowed WM-functions mask. Omitting GDK_FUNC_ALL so the WM
  // respects individual bit values rather than treating all as enabled.
  GdkWMFunction funcs = GDK_FUNC_MOVE;
  if (is_minimizable) funcs = static_cast<GdkWMFunction>(funcs | GDK_FUNC_MINIMIZE);
  if (is_maximizable) funcs = static_cast<GdkWMFunction>(funcs | GDK_FUNC_MAXIMIZE);
  if (gtk_window_get_resizable(window)) funcs = static_cast<GdkWMFunction>(funcs | GDK_FUNC_RESIZE);
  if (is_closable)    funcs = static_cast<GdkWMFunction>(funcs | GDK_FUNC_CLOSE);
  gdk_window_set_functions(gdk_win, funcs);
}

void LinuxWindowManager::SetAlwaysOnTop(bool v) {
  MWM_LOG_ID(id, "SetAlwaysOnTop v=%d", v);
  if (window) gtk_window_set_keep_above(window, v);
}

void LinuxWindowManager::SetAlwaysOnBottom(bool v) {
  MWM_LOG_ID(id, "SetAlwaysOnBottom v=%d", v);
  if (window) gtk_window_set_keep_below(window, v);
}

const gchar* LinuxWindowManager::GetTitle() {
  MWM_LOG_ID(id, "GetTitle");
  return window ? gtk_window_get_title(window) : "";
}

void LinuxWindowManager::SetTitle(const gchar* t) {
  MWM_LOG_ID(id, "SetTitle");
  if (window) gtk_window_set_title(window, t);
}

void LinuxWindowManager::SetTitleBarStyle(const gchar* style) {
  MWM_LOG_ID(id, "SetTitleBarStyle style=%s", style ? style : "(null)");
  if (!window) return;
  const bool hidden = g_strcmp0(style, "hidden") == 0;
  GtkWidget* hb = HeaderBarOf(window);
  if (hb) {
    gtk_widget_set_visible(hb, !hidden);
  }
  // Hidden custom chrome: drop CSD so GTK rounded shell does not show black
  // triangles under VirtualWindowFrame's ClipRRect on Linux.
  gtk_window_set_decorated(window, !hidden);
  if (hidden) {
    // app_paintable=true suppresses GTK's CSD shadow drawing, but on Wayland
    // the GDK layer still keeps internal shadow-extent fields (shadow_left,
    // shadow_top, ...) at ~26 px per side.  Those extents make
    // gtk_window_resize(W, H) request an OUTER size of WxH rather than a
    // content area of WxH, so the compositor delivers a configure-event with
    // (W-52)x(H-52) instead of WxH - exactly the 748x548 bug for an 800x600
    // target.  Calling gdk_window_set_shadow_width(0,0,0,0) zeroes out those
    // extents so that every resize call and every configure-event consistently
    // uses the content area as the reference size.
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
    GdkWindow* gdk_win = gtk_widget_get_window(GTK_WIDGET(window));
    if (gdk_win) {
      gdk_window_set_shadow_width(gdk_win, 0, 0, 0, 0);
      MWM_LOG_ID(id, "SetTitleBarStyle: shadow extents zeroed");
    }
  }
  if (title_bar_style) g_free(title_bar_style);
  title_bar_style = g_strdup(style);
}

int LinuxWindowManager::GetTitleBarHeight() {
  MWM_LOG_ID(id, "GetTitleBarHeight");
  if (!window) return 0;
  GtkWidget* hb = gtk_window_get_titlebar(window);
  const bool hidden =
      title_bar_style && g_strcmp0(title_bar_style, "hidden") == 0;
  if (!hidden && hb) return gtk_widget_get_allocated_height(hb);
  return 0;
}

bool LinuxWindowManager::IsSkipTaskbar() {
  MWM_LOG_ID(id, "IsSkipTaskbar");
  return window ? gtk_window_get_skip_taskbar_hint(window) : false;
}

void LinuxWindowManager::SetSkipTaskbar(bool v) {
  MWM_LOG_ID(id, "SetSkipTaskbar v=%d", v);
  if (window) gtk_window_set_skip_taskbar_hint(window, v);
}

bool LinuxWindowManager::SetIcon(const gchar* path) {
  MWM_LOG_ID(id, "SetIcon path=%s", path ? path : "(null)");
  if (!window) return false;
  return gtk_window_set_icon_from_file(window, path, nullptr);
}

double LinuxWindowManager::GetOpacity() {
  MWM_LOG_ID(id, "GetOpacity");
  return window ? gtk_widget_get_opacity(GTK_WIDGET(window)) : 1.0;
}

void LinuxWindowManager::SetOpacity(double o) {
  MWM_LOG_ID(id, "SetOpacity o=%f", o);
  if (window) gtk_widget_set_opacity(GTK_WIDGET(window), o);
}

void LinuxWindowManager::SetBrightness(const gchar* brightness) {
  MWM_LOG_ID(id, "SetBrightness brightness=%s",
             brightness ? brightness : "(null)");
  const gboolean dark = g_strcmp0(brightness, "dark") == 0;
  GtkSettings* settings = gtk_settings_get_default();
  g_object_set(settings, "gtk-application-prefer-dark-theme", dark, nullptr);
}

void LinuxWindowManager::PopUpWindowMenu() {
  MWM_LOG_ID(id, "PopUpWindowMenu");
  if (!window) return;
  auto* gdk = GetGdkWindow(window);
  if (!gdk) return;
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  int x, y;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  int ox, oy;
  gdk_window_get_origin(gdk, &ox, &oy);
  GdkEvent* e = gdk_event_new(GDK_BUTTON_PRESS);
  e->button.window = gdk;
  e->button.device = pointer;
  e->button.x_root = x;
  e->button.y_root = y;
  e->button.x = x - ox;
  e->button.y = y - oy;
  gdk_window_show_window_menu(gdk, e);
  gdk_event_free(e);
}

void LinuxWindowManager::StartDragging() {
  MWM_LOG_ID(id, "StartDragging");
  if (!window) return;
  auto screen = gtk_window_get_screen(window);
  auto display = gdk_screen_get_display(screen);
  auto seat = gdk_display_get_default_seat(display);
  auto device = gdk_seat_get_pointer(seat);
  gint rx, ry;
  gdk_device_get_position(device, nullptr, &rx, &ry);
  const guint pressed_button =
      last_button.button ? last_button.button : GDK_BUTTON_PRIMARY;
  const guint32 ts = last_button.time ? last_button.time
                                      : (guint32)g_get_monotonic_time();
  gtk_window_present(window);
  gtk_window_begin_move_drag(window, pressed_button, rx, ry, ts);
  is_dragging = true;
  EnsureDragReleaseWatcher();
}

void LinuxWindowManager::StartResizing(const gchar* edge) {
  MWM_LOG_ID(id, "StartResizing edge=%s", edge ? edge : "(null)");
  if (!window) return;
  ClearGdkAspectHints();
  memset(&last_button, 0, sizeof(last_button));
  last_button.type = GDK_BUTTON_PRESS;
  last_button.button = GDK_BUTTON_PRIMARY;
  GdkWindowEdge ge = GDK_WINDOW_EDGE_NORTH_WEST;
  if (g_strcmp0(edge, "topLeft") == 0)
    ge = GDK_WINDOW_EDGE_NORTH_WEST;
  else if (g_strcmp0(edge, "top") == 0)
    ge = GDK_WINDOW_EDGE_NORTH;
  else if (g_strcmp0(edge, "topRight") == 0)
    ge = GDK_WINDOW_EDGE_NORTH_EAST;
  else if (g_strcmp0(edge, "left") == 0)
    ge = GDK_WINDOW_EDGE_WEST;
  else if (g_strcmp0(edge, "right") == 0)
    ge = GDK_WINDOW_EDGE_EAST;
  else if (g_strcmp0(edge, "bottomLeft") == 0)
    ge = GDK_WINDOW_EDGE_SOUTH_WEST;
  else if (g_strcmp0(edge, "bottom") == 0)
    ge = GDK_WINDOW_EDGE_SOUTH;
  else if (g_strcmp0(edge, "bottomRight") == 0)
    ge = GDK_WINDOW_EDGE_SOUTH_EAST;

  auto screen = gtk_window_get_screen(window);
  auto display = gdk_screen_get_display(screen);
  auto seat = gdk_display_get_default_seat(display);
  auto device = gdk_seat_get_pointer(seat);
  gint rx, ry;
  gdk_device_get_position(device, nullptr, &rx, &ry);
  const guint pressed_button =
      last_button.button ? last_button.button : GDK_BUTTON_PRIMARY;
  const guint32 ts = last_button.time ? last_button.time
                                      : (guint32)g_get_monotonic_time();
  gtk_window_present(window);
  gtk_window_begin_resize_drag(window, ge, pressed_button, rx, ry, ts);
  is_resizing = true;
  EnsureDragReleaseWatcher();
}
