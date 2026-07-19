#ifndef MULTI_WINDOW_MANAGER_H_
#define MULTI_WINDOW_MANAGER_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "include/multi_window_manager/multi_window_manager_plugin.h"

class LinuxWindowManager {
 public:
  LinuxWindowManager();
  ~LinuxWindowManager();

  // ---- Process-wide state ----
  static std::mutex registry_mtx;
  static int64_t autoincrement_id;
  static std::map<int64_t, std::shared_ptr<LinuxWindowManager>> windows;
  static MultiWindowManagerPluginWindowCreatedCallback window_created_callback;

  // ---- Per-window state ----
  int64_t id = -1;
  GtkWindow* window = nullptr;
  FlMethodChannel* channel = nullptr;

  bool is_prevent_close = false;
  bool is_confirm_close = false;
  bool is_reuse_enabled = false;
  bool is_being_reused = false;
  bool is_in_reuse_pool = false;
  bool is_minimizable = true;
  bool is_maximizable = true;
  bool is_closable = true;


  GdkGeometry geometry{};
  GdkWindowHints hints = static_cast<GdkWindowHints>(0);
  float aspect_ratio = 0.0f;
  gint last_configure_width = 0;
  gint last_configure_height = 0;
  gint last_configure_x = 0;
  gint last_configure_y = 0;
  bool has_pending_move = false;
  gint pending_move_x = 0;
  gint pending_move_y = 0;
  GtkCssProvider* css_provider = nullptr;
  gchar* title_bar_style = nullptr;

  GdkEventButton last_button{};
  bool is_dragging = false;
  bool is_resizing = false;
  guint drag_release_watch_id = 0;
  int dock_state = 0;

  // ---- Window operations ----
  void SetAsFrameless();
  void Close();
  void Destroy();
  void Focus();
  bool IsFocused();
  void Show();
  void Hide();
  bool IsVisible();
  bool IsMaximized();
  void Maximize();
  void Unmaximize();
  bool IsMinimized();
  void Minimize();
  void Restore();
  bool IsDockable();
  int IsDocked();
  bool Dock(bool left, bool right, int width);
  bool Undock();
  bool IsFullScreen();
  void SetFullScreen(bool fs);
  void SetAspectRatio(float ar);
  void ClearGdkAspectHints();
  bool SetBackgroundColor(int r, int g, int b, int a);
  FlValue* GetBounds();
  void SetBounds(FlValue* args);
  void ApplyPendingMove();
  void SetMinimumSize(float w, float h);
  void SetMaximumSize(float w, float h);
  bool IsResizable();
  void SetResizable(bool v);
  bool IsMinimizable();
  void SetMinimizable(bool v);
  bool IsMaximizable();
  void SetMaximizable(bool v);
  bool IsClosable();
  void SetClosable(bool v);
  void ApplyWmFunctions();
  void SetAlwaysOnTop(bool v);
  void SetAlwaysOnBottom(bool v);
  const gchar* GetTitle();
  void SetTitle(const gchar* t);
  void SetTitleBarStyle(const gchar* style);
  int GetTitleBarHeight();
  bool IsSkipTaskbar();
  void SetSkipTaskbar(bool v);
  bool SetIcon(const gchar* path);
  double GetOpacity();
  void SetOpacity(double o);
  void SetBrightness(const gchar* brightness);
  void PopUpWindowMenu();
  void StartDragging();
  void StartResizing(const gchar* edge);

  /// After gtk_window_begin_*_drag, FlView may miss button-release (Flutter #74939).
  void FinishInteractiveWindowGesture();
  void StopDragReleaseWatcher();
  bool IsPointerButtonStillPressed() const;
  void EnsureDragReleaseWatcher();
  static gboolean DragReleaseWatchCb(gpointer data);
  void EmitSyntheticPointerRelease();
  void RestoreFlutterViewFocus();

  // ---- Event helpers ----
  static void EmitLocal(const std::shared_ptr<LinuxWindowManager>& wm,
                        const char* event_name);
  static void EmitGlobal(int64_t from_id, const char* event_name);

  // ---- Registry helpers ----
  static std::shared_ptr<LinuxWindowManager> GetTarget(int64_t fallback_id,
                                                       FlValue* args);
  static int64_t CreateWindow(const std::vector<std::string>& user_args);
  static void Unregister(int64_t id);

  /// Destroys every registered window except [keep_id] (bypasses reuse-hide).
  /// Used when the primary window closes so hidden reuse engines do not linger.
  static void ForceDestroyAllWindowsExcept(int64_t keep_id);

  // ---- Utility ----
  static GdkWindow* GetGdkWindow(GtkWindow* w);
  static GtkWidget* HeaderBarOf(GtkWindow* w);
  static FlValue* MakeBounds(GtkWindow* w);
};

#endif  // MULTI_WINDOW_MANAGER_H_
