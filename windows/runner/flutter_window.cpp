#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <wchar.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Register a MethodChannel for native window operations (e.g., flash taskbar)
  auto messenger = flutter_controller_->engine()->messenger();
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "simple_present/window",
      &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("flashTaskbar") == 0) {
          // Flash the taskbar icon (FlashWindowEx)
          FLASHWINFO fi;
          fi.cbSize = sizeof(fi);
          fi.hwnd = GetHandle();
          fi.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
          fi.uCount = 5;
          fi.dwTimeout = 0;
          FlashWindowEx(&fi);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name().compare("notify") == 0) {
          std::string title = "SimplePresent - today";
          std::string body = "";
          const flutter::EncodableValue* args = call.arguments();
          if (args) {
            const flutter::EncodableMap* map = std::get_if<flutter::EncodableMap>(args);
            if (map) {
              auto it = map->find(flutter::EncodableValue("title"));
              if (it != map->end() && !it->second.IsNull()) {
                if (std::holds_alternative<std::string>(it->second))
                  title = std::get<std::string>(it->second);
              }
              it = map->find(flutter::EncodableValue("body"));
              if (it != map->end() && !it->second.IsNull()) {
                if (std::holds_alternative<std::string>(it->second))
                  body = std::get<std::string>(it->second);
              }
            }
          }
          // Convert to wide strings
          std::wstring wtitle(title.begin(), title.end());
          std::wstring wbody(body.begin(), body.end());

          // Ensure an icon entry exists; try to add a simple icon if needed
          NOTIFYICONDATAW nidAdd = {};
          nidAdd.cbSize = sizeof(nidAdd);
          nidAdd.hWnd = GetHandle();
          nidAdd.uID = 2001;
          nidAdd.uFlags = NIF_ICON | NIF_TIP;
          nidAdd.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
          wcscpy_s(nidAdd.szTip, sizeof(nidAdd.szTip) / sizeof(wchar_t), L"SimplePresent");
          Shell_NotifyIconW(NIM_ADD, &nidAdd);

          NOTIFYICONDATAW nid = {};
          nid.cbSize = sizeof(nid);
          nid.hWnd = GetHandle();
          nid.uID = 2001;
          nid.uFlags = NIF_INFO;
          wcscpy_s(nid.szInfo, sizeof(nid.szInfo) / sizeof(wchar_t), wbody.c_str());
          wcscpy_s(nid.szInfoTitle, sizeof(nid.szInfoTitle) / sizeof(wchar_t), wtitle.c_str());
          nid.dwInfoFlags = NIIF_INFO;
          Shell_NotifyIconW(NIM_MODIFY, &nid);

          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name().compare("bringToFront") == 0) {
          HWND hwnd = GetHandle();
          if (hwnd) {
            // Restore if minimized
            if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
            else ShowWindow(hwnd, SW_SHOW);
            // Try to bring to foreground
            SetForegroundWindow(hwnd);
            // Also bring to top
            BringWindowToTop(hwnd);
            result->Success(flutter::EncodableValue(true));
            return;
          }
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (call.method_name().compare("setWindowGeometry") == 0) {
          const flutter::EncodableValue* args = call.arguments();
          if (args) {
            const flutter::EncodableMap* map = std::get_if<flutter::EncodableMap>(args);
            if (map) {
              // Handle always_on_top flag independently
              auto itAot = map->find(flutter::EncodableValue("always_on_top"));
              if (itAot != map->end() && !itAot->second.IsNull() && std::holds_alternative<bool>(itAot->second)) {
                HWND hwnd = GetHandle();
                bool aot = std::get<bool>(itAot->second);
                if (hwnd) {
                  if (aot) SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
                  else SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
                }
                result->Success(flutter::EncodableValue(true));
                return;
              }
              auto getInt = [&](const std::string& k) -> int {
                auto it = map->find(flutter::EncodableValue(k));
                if (it != map->end() && std::holds_alternative<int>(it->second))
                  return std::get<int>(it->second);
                return 0;
              };
              int x = getInt("x");
              int y = getInt("y");
              int w = getInt("width");
              int h = getInt("height");
              HWND hwnd = GetHandle();
              if (hwnd) {
                // Honor maximized flag if present
                auto itMax = map->find(flutter::EncodableValue("maximized"));
                bool maximized = false;
                if (itMax != map->end() && std::holds_alternative<bool>(itMax->second)) {
                  maximized = std::get<bool>(itMax->second);
                }
                if (maximized) {
                  ShowWindow(hwnd, SW_MAXIMIZE);
                } else {
                  // Ensure not maximized before setting geometry
                  ShowWindow(hwnd, SW_RESTORE);
                  SetWindowPos(hwnd, NULL, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
                }
                result->Success(flutter::EncodableValue(true));
                return;
              }
            }
          }
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (call.method_name().compare("getWindowGeometry") == 0) {
          HWND hwnd = GetHandle();
          if (hwnd) {
            RECT r;
            if (GetWindowRect(hwnd, &r)) {
              flutter::EncodableMap out;
              out[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int>(r.left));
              out[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int>(r.top));
              out[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int>(r.right - r.left));
              out[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int>(r.bottom - r.top));
              // Report always-on-top state
              bool isTopMost = (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
              out[flutter::EncodableValue("always_on_top")] = flutter::EncodableValue(isTopMost);
              // Report maximized state
              bool isMax = IsZoomed(hwnd) != 0;
              out[flutter::EncodableValue("maximized")] = flutter::EncodableValue(isMax);
              result->Success(flutter::EncodableValue(out));
              return;
            }
          }
          result->Success(flutter::EncodableValue(flutter::EncodableMap()));
          return;
        }
          if (call.method_name().compare("getScreenSize") == 0) {
            int sw = GetSystemMetrics(SM_CXSCREEN);
            int sh = GetSystemMetrics(SM_CYSCREEN);
            flutter::EncodableMap out;
            out[flutter::EncodableValue("width")] = flutter::EncodableValue(sw);
            out[flutter::EncodableValue("height")] = flutter::EncodableValue(sh);
            result->Success(flutter::EncodableValue(out));
            return;
          }
        result->NotImplemented();
      });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
