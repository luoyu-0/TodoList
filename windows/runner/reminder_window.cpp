#include "reminder_window.h"
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>

ReminderWindow::ReminderWindow(const flutter::DartProject& project,
                               std::function<void()> open)
    : project_(project), open_(std::move(open)) {
  project_.set_dart_entrypoint("reminderMain");
  project_.set_dart_entrypoint_arguments({});
}
ReminderWindow::~ReminderWindow() { Destroy(); }

bool ReminderWindow::Enqueue(const std::string& title) {
  if (!GetHandle() && !Create(L"TodoList 提醒", Point(0, 0), Size(400, 200))) {
    Destroy();
    return false;
  }
  queue_.push_back(title);
  Next();
  return true;
}

bool ReminderWindow::OnCreate() {
  const HWND hwnd = GetHandle();
  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE);
  Position();
  const RECT frame = GetClientArea();
  controller_ = std::make_unique<flutter::FlutterViewController>(frame.right, frame.bottom, project_);
  if (!controller_->engine() || !controller_->view()) return false;
  // 不调用 SetChildContent，避免其 SetFocus 抢走输入焦点。
  HWND child = controller_->view()->GetNativeWindow();
  SetParent(child, hwnd);
  MoveWindow(child, 0, 0, frame.right, frame.bottom, TRUE);
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      controller_->engine()->messenger(), "com.todolist/reminder_window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "ready") {
      ready_ = true;
      result->Success();
      Next();
    } else if (method == "present") {
      ShowWindow(GetHandle(), SW_SHOWNOACTIVATE);
      MessageBeep(MB_ICONEXCLAMATION);
      result->Success();
    } else if (method == "dismiss" || method == "open") {
      ShowWindow(GetHandle(), SW_HIDE);
      active_ = false;
      result->Success();
      if (method == "open") open_();
      PostMessage(GetHandle(), WM_APP + 10, 0, 0);
    } else {
      result->NotImplemented();
    }
  });
  controller_->ForceRedraw();
  return true;
}

void ReminderWindow::Position() {
  POINT cursor{};
  GetCursorPos(&cursor);
  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfo(monitor, &info)) return;
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const int margin = MulDiv(16, dpi, 96);
  const int width = std::min(MulDiv(400, dpi, 96),
      static_cast<int>(info.rcWork.right - info.rcWork.left) - margin * 2);
  const int height = MulDiv(200, dpi, 96);
  SetWindowPos(GetHandle(), HWND_TOPMOST, info.rcWork.right - width - margin,
      info.rcWork.bottom - height - margin, width, height, SWP_NOACTIVATE | SWP_FRAMECHANGED);
  // 优先使用系统合成器圆角，旧版 Windows 用裁剪兜底。
  const DWORD round = 2;
  if (FAILED(DwmSetWindowAttribute(GetHandle(), 33, &round, sizeof(round)))) {
    SetWindowRgn(GetHandle(), CreateRoundRectRgn(0, 0, width + 1, height + 1,
        MulDiv(24, dpi, 96), MulDiv(24, dpi, 96)), TRUE);
  } else {
    const MARGINS margins{1, 1, 1, 1};
    DwmExtendFrameIntoClientArea(GetHandle(), &margins);
  }
}

void ReminderWindow::Next() {
  if (!ready_ || active_ || queue_.empty()) return;
  active_ = true;
  Position();
  auto title = queue_.front();
  queue_.pop_front();
  channel_->InvokeMethod("show", std::make_unique<flutter::EncodableValue>(title));
}
void ReminderWindow::OnDestroy() {
  ready_ = false;
  active_ = false;
  queue_.clear();
  channel_.reset();
  controller_.reset();
}
LRESULT ReminderWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_ACTIVATE) return 0;
  if (message == WM_APP + 10) { Next(); return 0; }
  if (message == WM_CLOSE) {
    ShowWindow(hwnd, SW_HIDE);
    active_ = false;
    Next();
    return 0;
  }
  if (controller_) {
    if (message == WM_SIZE) {
      RECT frame = GetClientArea();
      MoveWindow(controller_->view()->GetNativeWindow(), 0, 0, frame.right, frame.bottom, TRUE);
    }
    auto result = controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
