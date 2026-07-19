#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "multi_window_manager/multi_window_manager_plugin.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"ephtodo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);

  MultiWindowManagerPluginSetWindowCreatedCallback(
      [](std::vector<std::string> command_line_arguments) {
        flutter::DartProject secondary_project(L"data");
        secondary_project.set_dart_entrypoint_arguments(
            std::move(command_line_arguments));
        auto secondary_window =
            std::make_shared<FlutterWindow>(secondary_project);
        Win32Window::Point secondary_origin(120, 120);
        Win32Window::Size secondary_size(380, 540);
        if (!secondary_window->Create(L"ephtodo sticky", secondary_origin,
                                      secondary_size)) {
          return std::shared_ptr<FlutterWindow>();
        }
        secondary_window->SetQuitOnClose(false);
        return secondary_window;
      });

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
