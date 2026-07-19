#include "include/multi_window_manager/multi_window_manager_plugin.h"
#include "include/multi_window_manager/mwm_log.h"

#include "multi_window_manager.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <multi_window_manager/mwm_per_window_channel.h>
#include <multi_window_manager/mwm_plugin_gtk_bridge.h>

#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#define MULTI_WINDOW_MANAGER_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), multi_window_manager_plugin_get_type(), \
                              MultiWindowManagerPlugin))

// ---- GObject plugin wrapper ----

struct _MultiWindowManagerPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  FlMethodChannel* bootstrap_channel;
  FlMethodChannel* static_channel;
  FlMethodChannel* screen_retriever_channel;
  FlEventChannel* screen_retriever_event_channel;
  int64_t current_id;
  guint button_press_signal_id;
  guint button_press_emission_hook_id;
  /// GtkWindow whose signals are connected with this instance as user_data.
  GtkWindow* mwm_signal_window;
};

G_DEFINE_TYPE(MultiWindowManagerPlugin, multi_window_manager_plugin,
              g_object_get_type())

// ---- Helpers ----

static GtkWindow* get_window_from_registrar(FlPluginRegistrar* registrar) {
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (!view) return nullptr;
  return GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static FlMethodResponse* ok_bool(bool v) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(v)));
}

static FlMethodResponse* ok_int(int64_t v) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_int(v)));
}

static FlMethodResponse* ok_string(const char* s) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(s ? s : "")));
}

static FlMethodResponse* err(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

// ---- invokeMethodToWindow plumbing ----

struct InvokeCtx {
  FlMethodCall* call;
  FlMethodChannel* target_ch;
};

static void invoke_finish_cb(GObject*, GAsyncResult* res, gpointer data) {
  std::unique_ptr<InvokeCtx> ctx(static_cast<InvokeCtx*>(data));
  g_autoptr(FlMethodResponse) resp =
      fl_method_channel_invoke_method_finish(ctx->target_ch, res, nullptr);

  MWM_LOG("invokeMethodToWindow finished (async)");

  if (FL_IS_METHOD_SUCCESS_RESPONSE(resp)) {
    FlValue* r =
        fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(resp));
    g_autoptr(FlMethodResponse) out = FL_METHOD_RESPONSE(
        fl_method_success_response_new(r ? fl_value_ref(r) : nullptr));
    fl_method_call_respond(ctx->call, out, nullptr);
  } else {
    g_autoptr(FlMethodResponse) out = FL_METHOD_RESPONSE(
        fl_method_error_response_new("invokeMethodToWindow",
                                     "Target invocation failed", nullptr));
    fl_method_call_respond(ctx->call, out, nullptr);
  }
  g_object_unref(ctx->call);
}

// ---- Per-window method handler ----

void mwm_per_window_method_call_cb(FlMethodChannel*,
                                   FlMethodCall* method_call,
                                   gpointer user_data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, args);


  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "waitUntilReadyToShow") == 0) {
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setAsFrameless") == 0) {
    if (wm) wm->SetAsFrameless();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "destroy") == 0) {
    if (wm) wm->Destroy();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "close") == 0) {
    if (wm) wm->Close();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "confirmClose") == 0) {
    if (wm && args) {
      wm->is_confirm_close =
          fl_value_get_bool(fl_value_lookup_string(args, "confirmClose"));
    }
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isPreventClose") == 0) {
    response = ok_bool(wm ? wm->is_prevent_close : false);
  } else if (g_strcmp0(method, "setPreventClose") == 0) {
    if (wm && args) {
      wm->is_prevent_close =
          fl_value_get_bool(fl_value_lookup_string(args, "isPreventClose"));
    }
    response = ok_bool(true);
  } else if (g_strcmp0(method, "focus") == 0) {
    if (wm) wm->Focus();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "blur") == 0) {
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isFocused") == 0) {
    response = ok_bool(wm ? wm->IsFocused() : false);
  } else if (g_strcmp0(method, "show") == 0) {
    if (wm) wm->Show();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "hide") == 0) {
    if (wm) wm->Hide();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isVisible") == 0) {
    response = ok_bool(wm ? wm->IsVisible() : false);
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    response = ok_bool(wm ? wm->IsMaximized() : false);
  } else if (g_strcmp0(method, "maximize") == 0) {
    if (wm) wm->Maximize();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "unmaximize") == 0) {
    if (wm) wm->Unmaximize();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isMinimized") == 0) {
    response = ok_bool(wm ? wm->IsMinimized() : false);
  } else if (g_strcmp0(method, "minimize") == 0) {
    if (wm) wm->Minimize();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "restore") == 0) {
    if (wm) wm->Restore();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isDockable") == 0) {
    response = ok_bool(wm ? wm->IsDockable() : false);
  } else if (g_strcmp0(method, "isDocked") == 0) {
    response = ok_int(wm ? wm->IsDocked() : 0);
  } else if (g_strcmp0(method, "dock") == 0) {
    if (!wm) {
      response = err("dock", "No window");
    } else {
      const bool left =
          fl_value_get_bool(fl_value_lookup_string(args, "left"));
      const bool right =
          fl_value_get_bool(fl_value_lookup_string(args, "right"));
      const int width = static_cast<int>(
          fl_value_get_int(fl_value_lookup_string(args, "width")));
      response = ok_bool(wm->Dock(left, right, width));
    }
  } else if (g_strcmp0(method, "undock") == 0) {
    if (!wm) {
      response = err("undock", "No window");
    } else {
      response = ok_bool(wm->Undock());
    }
  } else if (g_strcmp0(method, "isFullScreen") == 0) {
    response = ok_bool(wm ? wm->IsFullScreen() : false);
  } else if (g_strcmp0(method, "setFullScreen") == 0) {
    if (!wm) {
      response = err("setFullScreen", "No window");
    } else {
      bool fs =
          fl_value_get_bool(fl_value_lookup_string(args, "isFullScreen"));
      wm->SetFullScreen(fs);
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "setAspectRatio") == 0) {
    if (!wm) {
      response = err("setAspectRatio", "No window");
    } else {
      float ar = fl_value_get_float(fl_value_lookup_string(args, "aspectRatio"));
      wm->SetAspectRatio(ar);
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "setBackgroundColor") == 0) {
    if (!wm) {
      response = err("setBackgroundColor", "No window");
    } else {
      int r = fl_value_get_int(fl_value_lookup_string(args, "backgroundColorR"));
      int gv = fl_value_get_int(fl_value_lookup_string(args, "backgroundColorG"));
      int b = fl_value_get_int(fl_value_lookup_string(args, "backgroundColorB"));
      int a = fl_value_get_int(fl_value_lookup_string(args, "backgroundColorA"));
      if (wm->SetBackgroundColor(r, gv, b, a)) {
        response = ok_bool(true);
      } else {
        response = err("setBackgroundColor", "CSS load failed");
      }
    }
  } else if (g_strcmp0(method, "getBounds") == 0) {
    if (!wm || !wm->window) {
      response = err("getBounds", "No window");
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(wm->GetBounds()));
    }
  } else if (g_strcmp0(method, "setBounds") == 0) {
    if (!wm) {
      response = err("setBounds", "No window");
    } else {
      wm->SetBounds(args);
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "setMinimumSize") == 0) {
    if (!wm) {
      response = err("setMinimumSize", "No window");
    } else {
      float w = fl_value_get_float(fl_value_lookup_string(args, "width"));
      float h = fl_value_get_float(fl_value_lookup_string(args, "height"));
      wm->SetMinimumSize(w, h);
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "setMaximumSize") == 0) {
    if (!wm) {
      response = err("setMaximumSize", "No window");
    } else {
      float w = fl_value_get_float(fl_value_lookup_string(args, "width"));
      float h = fl_value_get_float(fl_value_lookup_string(args, "height"));
      wm->SetMaximumSize(w, h);
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "isResizable") == 0) {
    response = ok_bool(wm ? wm->IsResizable() : false);
  } else if (g_strcmp0(method, "setResizable") == 0) {
    if (wm && args)
      wm->SetResizable(
          fl_value_get_bool(fl_value_lookup_string(args, "isResizable")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isMinimizable") == 0) {
    response = ok_bool(wm ? wm->IsMinimizable() : true);
  } else if (g_strcmp0(method, "setMinimizable") == 0) {
    if (wm && args)
      wm->SetMinimizable(
          fl_value_get_bool(fl_value_lookup_string(args, "isMinimizable")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isMaximizable") == 0) {
    response = ok_bool(wm ? wm->IsMaximizable() : true);
  } else if (g_strcmp0(method, "setMaximizable") == 0) {
    if (wm && args)
      wm->SetMaximizable(
          fl_value_get_bool(fl_value_lookup_string(args, "isMaximizable")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isClosable") == 0) {
    response = ok_bool(wm ? wm->IsClosable() : false);
  } else if (g_strcmp0(method, "setClosable") == 0) {
    if (wm && args)
      wm->SetClosable(
          fl_value_get_bool(fl_value_lookup_string(args, "isClosable")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isAlwaysOnTop") == 0) {
    response = ok_bool(false);
  } else if (g_strcmp0(method, "setAlwaysOnTop") == 0) {
    if (wm && args)
      wm->SetAlwaysOnTop(
          fl_value_get_bool(fl_value_lookup_string(args, "isAlwaysOnTop")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "isAlwaysOnBottom") == 0) {
    response = ok_bool(false);
  } else if (g_strcmp0(method, "setAlwaysOnBottom") == 0) {
    if (wm && args)
      wm->SetAlwaysOnBottom(
          fl_value_get_bool(fl_value_lookup_string(args, "isAlwaysOnBottom")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "getTitle") == 0) {
    response = ok_string(wm ? wm->GetTitle() : "");
  } else if (g_strcmp0(method, "setTitle") == 0) {
    if (wm && args)
      wm->SetTitle(
          fl_value_get_string(fl_value_lookup_string(args, "title")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setTitleBarStyle") == 0) {
    if (!wm) {
      response = err("setTitleBarStyle", "No window");
    } else {
      wm->SetTitleBarStyle(
          fl_value_get_string(fl_value_lookup_string(args, "titleBarStyle")));
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "getTitleBarHeight") == 0) {
    response = ok_int(wm ? wm->GetTitleBarHeight() : 0);
  } else if (g_strcmp0(method, "isSkipTaskbar") == 0) {
    response = ok_bool(wm ? wm->IsSkipTaskbar() : false);
  } else if (g_strcmp0(method, "setSkipTaskbar") == 0) {
    if (wm && args)
      wm->SetSkipTaskbar(
          fl_value_get_bool(fl_value_lookup_string(args, "isSkipTaskbar")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setProgressBar") == 0) {
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setIcon") == 0) {
    if (!wm) {
      response = err("setIcon", "No window");
    } else {
      bool ok = wm->SetIcon(
          fl_value_get_string(fl_value_lookup_string(args, "iconPath")));
      response = ok_bool(ok);
    }
  } else if (g_strcmp0(method, "hasShadow") == 0) {
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setHasShadow") == 0) {
    response = ok_bool(true);
  } else if (g_strcmp0(method, "getOpacity") == 0) {
    double o = wm ? wm->GetOpacity() : 1.0;
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_float(o)));
  } else if (g_strcmp0(method, "setOpacity") == 0) {
    if (wm && args)
      wm->SetOpacity(
          fl_value_get_float(fl_value_lookup_string(args, "opacity")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setBrightness") == 0) {
    if (wm && args)
      wm->SetBrightness(
          fl_value_get_string(fl_value_lookup_string(args, "brightness")));
    response = ok_bool(true);
  } else if (g_strcmp0(method, "setIgnoreMouseEvents") == 0) {
    response = ok_bool(true);
  } else if (g_strcmp0(method, "popUpWindowMenu") == 0) {
    if (!wm) {
      response = err("popUpWindowMenu", "No window");
    } else {
      wm->PopUpWindowMenu();
      response = ok_bool(true);
    }
  } else if (g_strcmp0(method, "startDragging") == 0) {
    if (wm) wm->StartDragging();
    response = ok_bool(true);
  } else if (g_strcmp0(method, "startResizing") == 0) {
    if (wm && args) {
      const gchar* edge =
          fl_value_get_string(fl_value_lookup_string(args, "resizeEdge"));
      wm->StartResizing(edge);
    }
    response = ok_bool(true);
  } else if (g_strcmp0(method, "invokeMethodToWindow") == 0) {
    int64_t target_id =
        fl_value_get_int(fl_value_lookup_string(args, "targetWindowId"));
    FlValue* payload = fl_value_lookup_string(args, "args");
    auto twm = LinuxWindowManager::GetTarget(target_id, nullptr);
    if (!twm || !twm->channel) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invokeMethodToWindow", "targetWindowId not found", nullptr));
    } else {
      auto* ctx = new InvokeCtx{FL_METHOD_CALL(g_object_ref(method_call)),
                                twm->channel};
      fl_method_channel_invoke_method(twm->channel, "onEvent",
                                      payload ? fl_value_ref(payload) : nullptr,
                                      nullptr, invoke_finish_cb, ctx);
      return;
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ---- Bootstrap method handler (ensureInitialized) ----

static void bootstrap_method_call_cb(FlMethodChannel*,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  MWM_LOG("bootstrap method=%s", method);

  if (g_strcmp0(method, "ensureInitialized") == 0) {
    if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "ensureInitialized", "args required", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    FlValue* wid = fl_value_lookup_string(args, "windowId");
    if (!wid || fl_value_get_type(wid) != FL_VALUE_TYPE_INT) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "ensureInitialized", "windowId required", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const int64_t id = fl_value_get_int(wid);
    GtkWindow* gtk_window = get_window_from_registrar(plugin->registrar);

    std::shared_ptr<LinuxWindowManager> wm;
    bool hot_restart = false;
    {
      std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
      auto it = LinuxWindowManager::windows.find(id);
      if (it != LinuxWindowManager::windows.end() && it->second) {
        wm = it->second;
        hot_restart = true;
      }
    }

    if (!wm) {
      wm = std::make_shared<LinuxWindowManager>();
      wm->id = id;
    }
    wm->window = gtk_window;

    FlValue* reuse = fl_value_lookup_string(args, "isEnabledReuse");
    if (reuse && fl_value_get_type(reuse) == FL_VALUE_TYPE_BOOL) {
      wm->is_reuse_enabled = fl_value_get_bool(reuse);
    }

    // Hot restart: keep reuse-pool flags (Windows/macOS). Sync from GTK only
    // then - not on first launch, when secondaries start hidden (start_hidden)
    // but must still be shown by waitUntilReadyToShow / ReusableWindow.
    if (hot_restart && wm->is_reuse_enabled && wm->window) {
      if (!gtk_widget_get_visible(GTK_WIDGET(wm->window))) {
        wm->is_in_reuse_pool = true;
        wm->is_being_reused = false;
      } else {
        wm->is_in_reuse_pool = false;
      }
    }

    MWM_LOG_ID(id,
               "ensureInitialized gtk=%p hot_restart=%d reuse=%d in_pool=%d "
               "gtk_visible=%d",
               static_cast<void*>(gtk_window), hot_restart, wm->is_reuse_enabled,
               wm->is_in_reuse_pool,
               wm->window ? gtk_widget_get_visible(GTK_WIDGET(wm->window)) : 0);

    if (wm->channel) {
      g_object_unref(wm->channel);
      wm->channel = nullptr;
    }

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    const std::string ch = "multi_window_manager_" + std::to_string(id);
    wm->channel = fl_method_channel_new(
        fl_plugin_registrar_get_messenger(plugin->registrar), ch.c_str(),
        FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(
        wm->channel, mwm_per_window_method_call_cb, g_object_ref(plugin),
        g_object_unref);

    {
      std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
      LinuxWindowManager::windows[id] = wm;
    }

    plugin->current_id = id;
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(true)));
    fl_method_call_respond(method_call, response, nullptr);
    LinuxWindowManager::EmitGlobal(id, "initialized");
    return;
  }

  response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

// ---- Static method handler (createWindow, registry queries) ----

static void static_method_call_cb(FlMethodChannel*,
                                  FlMethodCall* method_call, gpointer) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  MWM_LOG("static channel method=%s", method);

  if (g_strcmp0(method, "createWindow") == 0) {
    std::vector<std::string> user_args;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* list = fl_value_lookup_string(args, "args");
      if (list && fl_value_get_type(list) == FL_VALUE_TYPE_LIST) {
        size_t len = fl_value_get_length(list);
        for (size_t i = 0; i < len; i++) {
          FlValue* v = fl_value_get_list_value(list, i);
          if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
            user_args.emplace_back(fl_value_get_string(v));
          }
        }
      }
    }
    int64_t id = LinuxWindowManager::CreateWindow(user_args);
    MWM_LOG_ID(id, "createWindow returned id (callback invoked)");
    if (id >= 0) {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_int(id)));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "createWindow", "WindowCreatedCallback is not set in runner",
          nullptr));
    }
  } else if (g_strcmp0(method, "getAllWindowManagerIds") == 0) {
    FlValue* list = fl_value_new_list();
    std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
    for (auto& pair : LinuxWindowManager::windows) {
      fl_value_append_take(list, fl_value_new_int(pair.first));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(method, "getActiveWindowIds") == 0) {
    FlValue* list = fl_value_new_list();
    std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
    for (auto& pair : LinuxWindowManager::windows) {
      auto& wm = pair.second;
      bool hidden = wm->is_reuse_enabled && wm->window &&
                    !gtk_widget_is_visible(GTK_WIDGET(wm->window)) &&
                    !wm->is_being_reused;
      if (!hidden) fl_value_append_take(list, fl_value_new_int(pair.first));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(method, "getHiddenWindowIds") == 0) {
    FlValue* list = fl_value_new_list();
    std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
    for (auto& pair : LinuxWindowManager::windows) {
      auto& wm = pair.second;
      if (wm->is_reuse_enabled && wm->window &&
          !gtk_widget_is_visible(GTK_WIDGET(wm->window)) &&
          !wm->is_being_reused) {
        fl_value_append_take(list, fl_value_new_int(pair.first));
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(method, "claimWindow") == 0) {
    int64_t target = -1;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* idv = fl_value_lookup_string(args, "windowId");
      if (idv && fl_value_get_type(idv) == FL_VALUE_TYPE_INT) {
        target = fl_value_get_int(idv);
      }
    }
    bool claimed = false;
    if (target >= 0) {
      std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
      auto it = LinuxWindowManager::windows.find(target);
      if (it != LinuxWindowManager::windows.end()) {
        auto& wm = it->second;
        if (wm->is_reuse_enabled && wm->window &&
            !gtk_widget_is_visible(GTK_WIDGET(wm->window)) &&
            !wm->is_being_reused) {
          wm->is_being_reused = true;
          claimed = true;
        }
      }
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(claimed)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ---- GTK signal handlers ----

static gboolean on_delete(GtkWidget*, GdkEvent*, gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  std::shared_ptr<LinuxWindowManager> wm;
  {
    std::lock_guard<std::mutex> lock(LinuxWindowManager::registry_mtx);
    auto it = LinuxWindowManager::windows.find(plugin->current_id);
    if (it != LinuxWindowManager::windows.end()) wm = it->second;
  }
  if (!wm) {
    MWM_LOG_ID(plugin->current_id,
               "delete_event: no wm in registry, allow destroy");
    return FALSE;
  }

  MWM_LOG_ID(wm->id,
             "delete_event: prevent=%d confirm=%d reuse=%d in_pool=%d",
             wm->is_prevent_close, wm->is_confirm_close,
             wm->is_reuse_enabled, wm->is_in_reuse_pool);

  if (wm->is_prevent_close) {
    LinuxWindowManager::EmitLocal(wm, "close");
    LinuxWindowManager::EmitGlobal(wm->id, "close");
    return TRUE;
  }
  if (!wm->is_confirm_close) {
    LinuxWindowManager::EmitLocal(wm, "confirm-close");
    LinuxWindowManager::EmitGlobal(wm->id, "confirm-close");
    return TRUE;
  }
  if (wm->is_reuse_enabled) {
    wm->is_in_reuse_pool = true;
    wm->is_confirm_close = false;
    LinuxWindowManager::EmitLocal(wm, "reuse-close");
    LinuxWindowManager::EmitGlobal(wm->id, "reuse-close");
    gtk_widget_hide(GTK_WIDGET(wm->window));
    return TRUE;
  }

  LinuxWindowManager::EmitLocal(wm, "close");
  LinuxWindowManager::EmitGlobal(wm->id, "close");

  // Keep a ref to the application before unregistering the window, because
  // Unregister() may release the last wm shared_ptr.
  GtkApplication* app = gtk_window_get_application(wm->window);
  LinuxWindowManager::Unregister(wm->id);

  // The primary window closing means the user wants to quit the app.
  // We manage app lifetime via g_application_hold(), so an explicit quit
  // is required here (Flutter's quit handler was detached for all windows).
  if (app && wm->id == 0) {
    g_application_quit(G_APPLICATION(app));
  }

  return FALSE;
}

static gboolean on_focus_in(GtkWidget*, GdkEvent*, gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm) return FALSE;
  LinuxWindowManager::EmitLocal(wm, "focus");
  LinuxWindowManager::EmitGlobal(wm->id, "focus");
  return FALSE;
}

static gboolean on_focus_out(GtkWidget*, GdkEvent*, gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm) return FALSE;
  LinuxWindowManager::EmitLocal(wm, "blur");
  LinuxWindowManager::EmitGlobal(wm->id, "blur");
  return FALSE;
}

static gboolean on_show(GtkWidget*, gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm) return FALSE;
  LinuxWindowManager::EmitLocal(wm, "show");
  LinuxWindowManager::EmitGlobal(wm->id, "show");
  if (wm->is_reuse_enabled) {
    LinuxWindowManager::EmitGlobal(wm->id, "reuse-show");
  }
  return FALSE;
}

static gboolean on_hide(GtkWidget*, gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm) return FALSE;
  LinuxWindowManager::EmitLocal(wm, "hide");
  LinuxWindowManager::EmitGlobal(wm->id, "hide");
  return FALSE;
}

static gboolean on_check_resize(GtkWidget*, gpointer) {
  // GtkWidget::check-resize is a layout hook, not a user resize. Emitting Dart
  // events here (especially with GDK_HINT_ASPECT) caused re-entrant crashes.
  return FALSE;
}

static gboolean on_event_after(GtkWidget*, GdkEvent* event, gpointer data) {
  if (!event || event->type != GDK_ENTER_NOTIFY) {
    return FALSE;
  }
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm || (!wm->is_dragging && !wm->is_resizing)) {
    return FALSE;
  }
  // ENTER_NOTIFY can fire while the WM drag is still active; wait until release.
  if (wm->IsPointerButtonStillPressed()) {
    return FALSE;
  }
  wm->FinishInteractiveWindowGesture();
  wm->StopDragReleaseWatcher();
  return FALSE;
}

static gboolean on_configure(GtkWidget*, GdkEvent* event, gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm || !event || event->type != GDK_CONFIGURE) return FALSE;

  const auto* cfg = &event->configure;
  const bool size_changed = cfg->width != wm->last_configure_width ||
                            cfg->height != wm->last_configure_height;
  const bool pos_changed = cfg->x != wm->last_configure_x ||
                           cfg->y != wm->last_configure_y;

  if (size_changed) {
    wm->last_configure_width = cfg->width;
    wm->last_configure_height = cfg->height;
    LinuxWindowManager::EmitLocal(wm, "resize");
    LinuxWindowManager::EmitGlobal(wm->id, "resize");
  } else if (pos_changed) {
    wm->last_configure_x = cfg->x;
    wm->last_configure_y = cfg->y;
    LinuxWindowManager::EmitLocal(wm, "move");
    LinuxWindowManager::EmitGlobal(wm->id, "move");
  }
  return FALSE;
}

// Deferred callbacks that undo disallowed maximize/minimize after GTK's signal
// emission has fully unwound. Calling gtk_window_unmaximize/deiconify directly
// inside window-state-event can be suppressed by GTK's reentrancy guard.
static gboolean enforce_unmaximize_cb(gpointer data) {
  auto* win = static_cast<GtkWindow*>(data);
  if (win && GTK_IS_WINDOW(win)) gtk_window_unmaximize(win);
  return G_SOURCE_REMOVE;
}

static gboolean enforce_deiconify_cb(gpointer data) {
  auto* win = static_cast<GtkWindow*>(data);
  if (win && GTK_IS_WINDOW(win)) gtk_window_deiconify(win);
  return G_SOURCE_REMOVE;
}

static gboolean on_state(GtkWidget*, GdkEventWindowState* event,
                         gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm) return FALSE;
  MWM_LOG_ID(wm->id, "signal window-state-event mask=%u state=%u",
             event->changed_mask, event->new_window_state);
  if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) {
    if (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) {
      if (!wm->is_maximizable) {
        // Defer unmaximize so GTK's reentrancy guard does not suppress it.
        g_idle_add(enforce_unmaximize_cb, wm->window);
      } else {
        LinuxWindowManager::EmitLocal(wm, "maximize");
        LinuxWindowManager::EmitGlobal(wm->id, "maximize");
      }
    } else {
      LinuxWindowManager::EmitLocal(wm, "unmaximize");
      LinuxWindowManager::EmitGlobal(wm->id, "unmaximize");
    }
  }
  if (event->changed_mask & GDK_WINDOW_STATE_ICONIFIED) {
    if (event->new_window_state & GDK_WINDOW_STATE_ICONIFIED) {
      if (!wm->is_minimizable) {
        // Defer deiconify so GTK's reentrancy guard does not suppress it.
        g_idle_add(enforce_deiconify_cb, wm->window);
      } else {
        LinuxWindowManager::EmitLocal(wm, "minimize");
        LinuxWindowManager::EmitGlobal(wm->id, "minimize");
      }
    } else {
      LinuxWindowManager::EmitLocal(wm, "restore");
      LinuxWindowManager::EmitGlobal(wm->id, "restore");
    }
  }
  if (event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) {
    if (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) {
      LinuxWindowManager::EmitLocal(wm, "enter-full-screen");
      LinuxWindowManager::EmitGlobal(wm->id, "enter-full-screen");
    } else {
      LinuxWindowManager::EmitLocal(wm, "leave-full-screen");
      LinuxWindowManager::EmitGlobal(wm->id, "leave-full-screen");
    }
  }
  return FALSE;
}

static gboolean on_mouse_press_hook(GSignalInvocationHint*, guint,
                                    const GValue* param_values,
                                    gpointer data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(data);
  auto wm = LinuxWindowManager::GetTarget(plugin->current_id, nullptr);
  if (!wm) return TRUE;
  auto* eb = static_cast<GdkEventButton*>(g_value_get_boxed(param_values + 1));
  if (!eb) return TRUE;
  memset(&wm->last_button, 0, sizeof(wm->last_button));
  memcpy(&wm->last_button, eb, sizeof(wm->last_button));
  return TRUE;
}

void mwm_plugin_bridge_connect_gtk_window_signals(GtkWindow* window,
                                                  gpointer plugin) {
  auto* p = MULTI_WINDOW_MANAGER_PLUGIN(plugin);
  p->mwm_signal_window = window;
  g_signal_connect(window, "delete_event", G_CALLBACK(on_delete), plugin);
  g_signal_connect(window, "focus-in-event", G_CALLBACK(on_focus_in), plugin);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(on_focus_out), plugin);
  g_signal_connect(window, "show", G_CALLBACK(on_show), plugin);
  g_signal_connect(window, "hide", G_CALLBACK(on_hide), plugin);
  g_signal_connect(window, "check-resize", G_CALLBACK(on_check_resize), plugin);
  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure), plugin);
  g_signal_connect(window, "window-state-event", G_CALLBACK(on_state), plugin);
  g_signal_connect(window, "event-after", G_CALLBACK(on_event_after), plugin);
}

void mwm_plugin_bridge_disconnect_gtk_window_signals(GtkWindow* window,
                                                     gpointer plugin) {
  if (!window || !plugin) return;
  if (!GTK_IS_WINDOW(window)) return;
  g_signal_handlers_disconnect_matched(
      G_OBJECT(window),
      static_cast<GSignalMatchType>(G_SIGNAL_MATCH_DATA), 0,
      static_cast<GQuark>(0), nullptr, nullptr, plugin);
  MULTI_WINDOW_MANAGER_PLUGIN(plugin)->mwm_signal_window = nullptr;
}

// ---- Plugin lifecycle ----

static void multi_window_manager_plugin_dispose(GObject* object) {
  auto* self = MULTI_WINDOW_MANAGER_PLUGIN(object);
  if (self->mwm_signal_window && GTK_IS_WINDOW(self->mwm_signal_window)) {
    mwm_plugin_bridge_disconnect_gtk_window_signals(self->mwm_signal_window,
                                                    self);
  }
  if (self->button_press_emission_hook_id != 0 &&
      self->button_press_signal_id != 0) {
    MWM_LOG_ID(self->current_id,
               "dispose: removing button-press emission hook id=%u",
               self->button_press_emission_hook_id);
    g_signal_remove_emission_hook(self->button_press_signal_id,
                                  self->button_press_emission_hook_id);
    self->button_press_emission_hook_id = 0;
    self->button_press_signal_id = 0;
  }
  if (self->bootstrap_channel) g_object_unref(self->bootstrap_channel);
  if (self->static_channel) g_object_unref(self->static_channel);
  if (self->screen_retriever_channel) g_object_unref(self->screen_retriever_channel);
  if (self->screen_retriever_event_channel) g_object_unref(self->screen_retriever_event_channel);
  if (self->registrar) g_object_unref(self->registrar);
  self->bootstrap_channel = nullptr;
  self->static_channel = nullptr;
  self->screen_retriever_channel = nullptr;
  self->screen_retriever_event_channel = nullptr;
  self->registrar = nullptr;
  G_OBJECT_CLASS(multi_window_manager_plugin_parent_class)->dispose(object);
}

static void multi_window_manager_plugin_class_init(
    MultiWindowManagerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = multi_window_manager_plugin_dispose;
}

static void multi_window_manager_plugin_init(MultiWindowManagerPlugin* self) {
  self->registrar = nullptr;
  self->bootstrap_channel = nullptr;
  self->static_channel = nullptr;
  self->screen_retriever_channel = nullptr;
  self->screen_retriever_event_channel = nullptr;
  self->current_id = -1;
  self->button_press_signal_id = 0;
  self->button_press_emission_hook_id = 0;
  self->mwm_signal_window = nullptr;
}

// ---- Screen Retriever ----

static FlValue* mwm_monitor_to_fl_value(GdkMonitor* monitor, int idx) {
  GdkRectangle geometry, workarea;
  gdk_monitor_get_geometry(monitor, &geometry);
  gdk_monitor_get_workarea(monitor, &workarea);
  const char* model = gdk_monitor_get_model(monitor);
  int scale = gdk_monitor_get_scale_factor(monitor);

  char id_buf[32];
  snprintf(id_buf, sizeof(id_buf), "%d", idx);

  FlValue* size_map = fl_value_new_map();
  fl_value_set_string_take(size_map, "width",
                           fl_value_new_float(static_cast<double>(geometry.width)));
  fl_value_set_string_take(size_map, "height",
                           fl_value_new_float(static_cast<double>(geometry.height)));

  FlValue* vis_pos_map = fl_value_new_map();
  fl_value_set_string_take(vis_pos_map, "dx",
                           fl_value_new_float(static_cast<double>(workarea.x)));
  fl_value_set_string_take(vis_pos_map, "dy",
                           fl_value_new_float(static_cast<double>(workarea.y)));

  FlValue* vis_size_map = fl_value_new_map();
  fl_value_set_string_take(vis_size_map, "width",
                           fl_value_new_float(static_cast<double>(workarea.width)));
  fl_value_set_string_take(vis_size_map, "height",
                           fl_value_new_float(static_cast<double>(workarea.height)));

  FlValue* m = fl_value_new_map();
  fl_value_set_string_take(m, "id", fl_value_new_string(id_buf));
  fl_value_set_string_take(m, "name", fl_value_new_string(model ? model : ""));
  fl_value_set_string_take(m, "size", size_map);
  fl_value_set_string_take(m, "visiblePosition", vis_pos_map);
  fl_value_set_string_take(m, "visibleSize", vis_size_map);
  fl_value_set_string_take(m, "scaleFactor",
                           fl_value_new_float(static_cast<double>(scale)));
  return m;
}

static void mwm_screen_retriever_emit_event(MultiWindowManagerPlugin* plugin,
                                            const char* event_name) {
  if (!plugin->screen_retriever_event_channel) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string(event_name));
  fl_event_channel_send(plugin->screen_retriever_event_channel, event, nullptr, nullptr);
}

static void mwm_on_monitor_added(GdkDisplay*, GdkMonitor*, gpointer user_data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(user_data);
  mwm_screen_retriever_emit_event(plugin, "display-added");
}

static void mwm_on_monitor_removed(GdkDisplay*, GdkMonitor*, gpointer user_data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(user_data);
  mwm_screen_retriever_emit_event(plugin, "display-removed");
}

static FlMethodResponse* mwm_screen_retriever_get_cursor_point() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return err("no_display", "No GDK display");

  GdkDevice* pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  gint x = 0, y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "dx",
                           fl_value_new_float(static_cast<double>(x)));
  fl_value_set_string_take(result, "dy",
                           fl_value_new_float(static_cast<double>(y)));
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_ref(result)));
}

static FlMethodResponse* mwm_screen_retriever_get_primary_display() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return err("no_display", "No GDK display");

  GdkMonitor* primary = gdk_display_get_primary_monitor(display);
  if (!primary) primary = gdk_display_get_monitor(display, 0);
  if (!primary) return err("no_monitor", "No primary monitor found");

  g_autoptr(FlValue) result = mwm_monitor_to_fl_value(primary, 0);
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_ref(result)));
}

static FlMethodResponse* mwm_screen_retriever_get_all_displays() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return err("no_display", "No GDK display");

  int n = gdk_display_get_n_monitors(display);
  g_autoptr(FlValue) list = fl_value_new_list();
  for (int i = 0; i < n; i++) {
    GdkMonitor* mon = gdk_display_get_monitor(display, i);
    fl_value_append_take(list, mwm_monitor_to_fl_value(mon, i));
  }

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string(result, "displays", fl_value_ref(list));
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_ref(result)));
}

static void screen_retriever_method_call_cb(FlMethodChannel*,
                                            FlMethodCall* call,
                                            gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "getCursorScreenPoint") == 0) {
    response = mwm_screen_retriever_get_cursor_point();
  } else if (g_strcmp0(method, "getPrimaryDisplay") == 0) {
    response = mwm_screen_retriever_get_primary_display();
  } else if (g_strcmp0(method, "getAllDisplays") == 0) {
    response = mwm_screen_retriever_get_all_displays();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(call, response, nullptr);
}

static FlMethodErrorResponse* screen_retriever_listen_cb(FlEventChannel*,
                                                          FlValue*,
                                                          gpointer user_data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(user_data);
  GdkDisplay* display = gdk_display_get_default();
  if (display) {
    g_signal_connect(display, "monitor-added",
                     G_CALLBACK(mwm_on_monitor_added), plugin);
    g_signal_connect(display, "monitor-removed",
                     G_CALLBACK(mwm_on_monitor_removed), plugin);
  }
  return nullptr;
}

static FlMethodErrorResponse* screen_retriever_cancel_cb(FlEventChannel*,
                                                          FlValue*,
                                                          gpointer user_data) {
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(user_data);
  GdkDisplay* display = gdk_display_get_default();
  if (display) {
    g_signal_handlers_disconnect_by_func(
        display, reinterpret_cast<gpointer>(mwm_on_monitor_added), plugin);
    g_signal_handlers_disconnect_by_func(
        display, reinterpret_cast<gpointer>(mwm_on_monitor_removed), plugin);
  }
  return nullptr;
}

// ---- Public API ----

void MultiWindowManagerPluginSetWindowCreatedCallback(
    MultiWindowManagerPluginWindowCreatedCallback callback) {
  MWM_LOG("SetWindowCreatedCallback callback=%p",
          reinterpret_cast<void*>(callback));
  LinuxWindowManager::window_created_callback = callback;
}

// ---------------------------------------------------------------------------
// multi_window_manager_linux_activate – library-managed window creation
// ---------------------------------------------------------------------------

static GtkApplication* g_mwm_activate_app = nullptr;
static MwmRegisterPluginsFunc g_mwm_register_plugins = nullptr;

static void mwm_internal_create_flutter_window(GtkApplication* application,
                                               const std::vector<std::string>& args) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    if (g_strcmp0(gdk_x11_screen_get_window_manager_name(screen), "GNOME Shell") != 0)
      use_header_bar = FALSE;
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* hb = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(hb));
    gtk_header_bar_set_show_close_button(hb, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(hb));
  }
  gtk_window_set_default_size(window, 1280, 720);

  gchar** c_args = g_new0(gchar*, args.size() + 1);
  for (size_t i = 0; i < args.size(); i++) c_args[i] = g_strdup(args[i].c_str());
  g_object_set_data_full(G_OBJECT(window), "mwm_dart_args", c_args,
                         (GDestroyNotify)g_strfreev);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, c_args);

  FlView* view = fl_view_new(project);
  GdkRGBA bg = {};
  fl_view_set_background_color(view, &bg);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_realize(GTK_WIDGET(view));

  g_mwm_register_plugins(FL_PLUGIN_REGISTRY(view));
  multi_window_manager_linux_detach_flutter_quit_on_window_close(window, view);
}

static void mwm_internal_window_created_cb(std::vector<std::string> dart_args) {
  struct Ctx {
    GtkApplication* app;
    std::vector<std::string> args;
  };
  auto* ctx = new Ctx{g_mwm_activate_app, std::move(dart_args)};
  g_main_context_invoke(
      nullptr,
      [](gpointer data) -> gboolean {
        std::unique_ptr<Ctx> c(static_cast<Ctx*>(data));
        mwm_internal_create_flutter_window(c->app, c->args);
        return G_SOURCE_REMOVE;
      },
      ctx);
}

extern "C" void multi_window_manager_linux_init(GtkApplication* app,
                                                MwmRegisterPluginsFunc register_plugins) {
  g_mwm_activate_app = app;
  g_mwm_register_plugins = register_plugins;
  g_application_hold(G_APPLICATION(app));
  MultiWindowManagerPluginSetWindowCreatedCallback(mwm_internal_window_created_cb);
}

extern "C" void multi_window_manager_linux_activate(GtkApplication* app,
                                                    char** dart_args,
                                                    MwmRegisterPluginsFunc register_plugins) {
  multi_window_manager_linux_init(app, register_plugins);

  std::vector<std::string> args;
  if (dart_args)
    for (int i = 0; dart_args[i]; i++) args.emplace_back(dart_args[i]);
  mwm_internal_create_flutter_window(app, args);
}

extern "C" void multi_window_manager_linux_detach_flutter_quit_on_window_close(
    GtkWindow* window,
    FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));

  const guint signal_id = g_signal_lookup("delete-event", GTK_TYPE_WIDGET);
  if (signal_id == 0) {
    MWM_LOG("detach_flutter_quit_on_window_close: delete-event lookup failed");
    return;
  }

  g_signal_handlers_disconnect_matched(
      G_OBJECT(window),
      static_cast<GSignalMatchType>(G_SIGNAL_MATCH_ID | G_SIGNAL_MATCH_DATA),
      signal_id, static_cast<GQuark>(0), nullptr, nullptr, view);
}

void multi_window_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  MWM_LOG("register_with_registrar registrar=%p",
          static_cast<void*>(registrar));
  auto* plugin = MULTI_WINDOW_MANAGER_PLUGIN(
      g_object_new(multi_window_manager_plugin_get_type(), nullptr));

  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->bootstrap_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "multi_window_manager", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->bootstrap_channel, bootstrap_method_call_cb,
      g_object_ref(plugin), g_object_unref);

  plugin->static_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "multi_window_manager_static",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->static_channel, static_method_call_cb, g_object_ref(plugin),
      g_object_unref);

  plugin->screen_retriever_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "multi_window_manager/screen_retriever",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->screen_retriever_channel, screen_retriever_method_call_cb,
      g_object_ref(plugin), g_object_unref);

  plugin->screen_retriever_event_channel =
      fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           "multi_window_manager/screen_retriever_event",
                           FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      plugin->screen_retriever_event_channel,
      screen_retriever_listen_cb, screen_retriever_cancel_cb,
      g_object_ref(plugin), g_object_unref);

  GtkWindow* window = get_window_from_registrar(registrar);
  if (window) {
    mwm_plugin_bridge_connect_gtk_window_signals(window, plugin);
  }

  plugin->button_press_signal_id =
      g_signal_lookup("button-press-event", GTK_TYPE_WIDGET);
  if (plugin->button_press_signal_id != 0) {
    plugin->button_press_emission_hook_id = g_signal_add_emission_hook(
        plugin->button_press_signal_id, 0, on_mouse_press_hook, plugin,
        nullptr);
    MWM_LOG("registered global button-press emission hook id=%u",
            plugin->button_press_emission_hook_id);
  } else {
    MWM_LOG("g_signal_lookup(button-press-event) failed");
  }

  g_object_unref(plugin);
}
