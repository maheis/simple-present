#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <wchar.h>

#include "flutter/generated_plugin_registrant.h"

// Helper: convert UTF-8 std::string to UTF-16 std::wstring on Windows
static std::wstring utf8_to_wstring(const std::string &s)
{
  if (s.empty())
    return std::wstring();
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), NULL, 0);
  if (size_needed <= 0)
    return std::wstring(s.begin(), s.end());
  std::wstring wstr(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &wstr[0], size_needed);
  return wstr;
}

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate()
{
  if (!Win32Window::OnCreate())
  {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view())
  {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]()
                                                      { this->Show(); });

  // Register a MethodChannel for native window operations (e.g., flash taskbar)
  auto messenger = flutter_controller_->engine()->messenger();
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "simple_present/window",
      &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue> &call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
      {
        if (call.method_name() == "enableWindowGeometryTracking")
        {
          track_geometry_ = true;
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name().compare("flashTaskbar") == 0)
        {
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
        if (call.method_name().compare("notify") == 0)
        {
          std::string title = "SimplePresent - today";
          std::string body = "";
          const flutter::EncodableValue *args = call.arguments();
          if (args)
          {
            const flutter::EncodableMap *map = std::get_if<flutter::EncodableMap>(args);
            if (map)
            {
              auto it = map->find(flutter::EncodableValue("title"));
              if (it != map->end() && !it->second.IsNull())
              {
                if (std::holds_alternative<std::string>(it->second))
                  title = std::get<std::string>(it->second);
              }
              it = map->find(flutter::EncodableValue("body"));
              if (it != map->end() && !it->second.IsNull())
              {
                if (std::holds_alternative<std::string>(it->second))
                  body = std::get<std::string>(it->second);
              }
            }
          }
          // Prefer window title if available
          HWND hwnd = GetHandle();
          std::wstring wtitle;
          if (hwnd)
          {
            wchar_t buf[512] = {0};
            if (GetWindowTextW(hwnd, buf, sizeof(buf) / sizeof(wchar_t)))
            {
              wtitle = buf;
            }
          }
          if (wtitle.empty())
          {
            wtitle = utf8_to_wstring(title);
          }
          std::wstring wbody = utf8_to_wstring(body);

          // Ensure an icon entry exists; try to use the window's icon
          NOTIFYICONDATAW nidAdd = {};
          nidAdd.cbSize = sizeof(nidAdd);
          nidAdd.hWnd = GetHandle();
          nidAdd.uID = 2001;
          nidAdd.uFlags = NIF_ICON | NIF_TIP;
          HICON hIcon = NULL;
          // If caller provided an explicit icon path, try to load it first
          if (args)
          {
            const flutter::EncodableMap *amap = std::get_if<flutter::EncodableMap>(args);
            if (amap)
            {
              auto itIcon = amap->find(flutter::EncodableValue("icon"));
              if (itIcon != amap->end() && !itIcon->second.IsNull() && std::holds_alternative<std::string>(itIcon->second))
              {
                std::string iconRel = std::get<std::string>(itIcon->second);
                // Build candidate full path relative to exe directory
                wchar_t modulePath[MAX_PATH + 1];
                if (GetModuleFileNameW(nullptr, modulePath, MAX_PATH) > 0)
                {
                  std::wstring mp(modulePath);
                  // strip filename
                  size_t pos = mp.find_last_of(L"\\/");
                  if (pos != std::wstring::npos)
                    mp = mp.substr(0, pos + 1);
                  // convert iconRel to wstring
                  std::wstring wrel = utf8_to_wstring(iconRel);
                  std::wstring full = mp + wrel;
                  // try to load icon from file
                  HICON loaded = (HICON)LoadImageW(NULL, full.c_str(), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
                  if (loaded)
                    hIcon = loaded;
                }
              }
            }
          }
          if (hwnd)
          {
            hIcon = (HICON)SendMessage(hwnd, WM_GETICON, ICON_SMALL, 0);
            if (!hIcon)
              hIcon = (HICON)GetClassLongPtr(hwnd, GCLP_HICONSM);
            if (!hIcon)
              hIcon = (HICON)GetClassLongPtr(hwnd, GCLP_HICON);
          }
          if (!hIcon)
            hIcon = LoadIcon(nullptr, IDI_APPLICATION);
          nidAdd.hIcon = hIcon;
          // Set tooltip to the window title (app name)
          wcscpy_s(nidAdd.szTip, sizeof(nidAdd.szTip) / sizeof(wchar_t), wtitle.c_str());
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
        if (call.method_name().compare("bringToFront") == 0)
        {
          HWND hwnd = GetHandle();
          if (hwnd)
          {
            // Restore if minimized
            if (IsIconic(hwnd))
              ShowWindow(hwnd, SW_RESTORE);
            else
              ShowWindow(hwnd, SW_SHOW);
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
        if (call.method_name().compare("setWindowGeometry") == 0)
        {
          const flutter::EncodableValue *args = call.arguments();
          if (args)
          {
            const flutter::EncodableMap *map = std::get_if<flutter::EncodableMap>(args);
            if (map)
            {
              HWND hwnd = GetHandle();
              auto getInt = [&](const std::string &k) -> int
              {
                auto it = map->find(flutter::EncodableValue(k));
                if (it != map->end() && std::holds_alternative<int>(it->second))
                  return std::get<int>(it->second);
                return 0;
              };
              int x = getInt("x");
              int y = getInt("y");
              int w = getInt("width");
              int h = getInt("height");
              if (hwnd)
              {
                // Honor maximized flag if present
                auto itMax = map->find(flutter::EncodableValue("maximized"));
                bool maximized = false;
                if (itMax != map->end() && std::holds_alternative<bool>(itMax->second))
                {
                  maximized = std::get<bool>(itMax->second);
                }
                ShowWindow(hwnd, SW_RESTORE);
                SetWindowPos(hwnd, NULL, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
                if (maximized)
                  ShowWindow(hwnd, SW_MAXIMIZE);
                result->Success(flutter::EncodableValue(true));
                return;
              }
            }
          }
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (call.method_name().compare("getWindowGeometry") == 0)
        {
          HWND hwnd = GetHandle();
          if (hwnd)
          {
            RECT r;
            if (GetWindowRect(hwnd, &r))
            {
              if (IsZoomed(hwnd) || IsIconic(hwnd))
              {
                WINDOWPLACEMENT placement = {};
                placement.length = sizeof(placement);
                if (GetWindowPlacement(hwnd, &placement))
                {
                  r = placement.rcNormalPosition;
                  const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                  MONITORINFO monitor_info = {};
                  monitor_info.cbSize = sizeof(monitor_info);
                  if (GetMonitorInfo(monitor, &monitor_info))
                  {
                    OffsetRect(&r, monitor_info.rcWork.left - monitor_info.rcMonitor.left,
                               monitor_info.rcWork.top - monitor_info.rcMonitor.top);
                  }
                }
              }
              flutter::EncodableMap out;
              out[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int>(r.left));
              out[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int>(r.top));
              out[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int>(r.right - r.left));
              out[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int>(r.bottom - r.top));
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
        if (call.method_name().compare("closeWindow") == 0)
        {
          HWND hwnd = GetHandle();
          if (hwnd)
          {
            // Queue the close so the method result can reach Dart first.
            allow_close_ = true;
            PostMessageW(hwnd, WM_CLOSE, 0, 0);
            result->Success(flutter::EncodableValue(true));
            return;
          }
          result->Success(flutter::EncodableValue(false));
          return;
        }
        if (call.method_name().compare("getScreenSize") == 0)
        {
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

void FlutterWindow::OnDestroy()
{
  if (flutter_controller_)
  {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept
{
  if (message == WM_CLOSE && track_geometry_ && !allow_close_ && method_channel_)
  {
    method_channel_->InvokeMethod("closeRequested", nullptr);
    return 0;
  }
  if (message == WM_EXITSIZEMOVE && track_geometry_ && method_channel_)
  {
    method_channel_->InvokeMethod("windowGeometryChanged", nullptr);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_)
  {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result)
    {
      return *result;
    }
  }

  switch (message)
  {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
