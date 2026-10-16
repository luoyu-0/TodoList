#ifndef RUNNER_REMINDER_WINDOW_H_
#define RUNNER_REMINDER_WINDOW_H_
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <deque>
#include <functional>
#include "win32_window.h"

// 独立渲染并复用，不初始化主窗口插件。
class ReminderWindow : public Win32Window {
 public:
  ReminderWindow(const flutter::DartProject& project, std::function<void()> open);
  ~ReminderWindow() override;
  bool Enqueue(const std::string& title);
 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept override;
 private:
  void Next();
  void Position();
  flutter::DartProject project_;
  std::function<void()> open_;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::deque<std::string> queue_;
  bool ready_ = false;
  bool active_ = false;
};
#endif
