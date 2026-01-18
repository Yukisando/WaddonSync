#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlwapi.h>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "shlwapi.lib")

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Force working directory to exe location (critical for Release builds)
  wchar_t exePath[MAX_PATH];
  GetModuleFileName(nullptr, exePath, MAX_PATH);
  PathRemoveFileSpec(exePath);
  SetCurrentDirectory(exePath);

  // Single instance check using Global mutex (works across integrity levels)
  HANDLE hMutex = CreateMutex(NULL, TRUE, L"Global\\WaddonSync_SingleInstance_Mutex");
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is already running, bring it to front
    HWND existingWindow = FindWindow(NULL, L"WaddonSync");
    if (existingWindow != NULL) {
      // Restore if minimized
      if (IsIconic(existingWindow)) {
        ShowWindow(existingWindow, SW_RESTORE);
      }
      // Bring to foreground
      SetForegroundWindow(existingWindow);
      // Flash the window to get user attention
      FlashWindow(existingWindow, TRUE);
    }
    if (hMutex) {
      CloseHandle(hMutex);
    }
    return EXIT_SUCCESS;
  }

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
  if (!window.Create(L"WaddonSync", origin, size)) {
    MessageBox(NULL, L"Failed to create window", L"Error", MB_OK | MB_ICONERROR);
    if (hMutex) {
      ReleaseMutex(hMutex);
      CloseHandle(hMutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  
  // Release the mutex when exiting
  if (hMutex) {
    ReleaseMutex(hMutex);
    CloseHandle(hMutex);
  }
  
  return EXIT_SUCCESS;
}
