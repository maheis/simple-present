#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

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
          std::string title = "SimplePresent";
          std::string body = "";
          const auto& args = call.arguments();
          if (std::holds_alternative<flutter::EncodableMap>(args)) {
            auto map = std::get<flutter::EncodableMap>(args);
            auto it = map.find(flutter::EncodableValue("title"));
            if (it != map.end() && std::holds_alternative<std::string>(it->second))
              title = std::get<std::string>(it->second);
            it = map.find(flutter::EncodableValue("body"));
            if (it != map.end() && std::holds_alternative<std::string>(it->second))
              body = std::get<std::string>(it->second);
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
          wcsncpy(nidAdd.szTip, L"SimplePresent", sizeof(nidAdd.szTip) / sizeof(wchar_t) - 1);
          Shell_NotifyIconW(NIM_ADD, &nidAdd);

          NOTIFYICONDATAW nid = {};
          nid.cbSize = sizeof(nid);
          nid.hWnd = GetHandle();
          nid.uID = 2001;
          nid.uFlags = NIF_INFO;
          wcsncpy(nid.szInfo, wbody.c_str(), sizeof(nid.szInfo) / sizeof(wchar_t) - 1);
          wcsncpy(nid.szInfoTitle, wtitle.c_str(), sizeof(nid.szInfoTitle) / sizeof(wchar_t) - 1);
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
