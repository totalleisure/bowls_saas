#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

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
  saved_login_channel_ = CreateSavedLoginChannel(
      flutter_controller_->engine()->messenger(), GetHandle());
  title_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "bowls/window_title",
      &flutter::StandardMethodCodec::GetInstance());
  wchar_t initial_title[256] = {};
  GetWindowTextW(GetHandle(), initial_title, 256);
  title_channel_->SetMethodCallHandler(
      [this, original = std::wstring(initial_title)](const auto& call, auto result) {
        if (call.method_name() == "reset") {
          SetWindowTextW(GetHandle(), original.c_str());
          result->Success();
        } else if (call.method_name() == "set" && call.arguments() &&
                   std::holds_alternative<std::string>(*call.arguments())) {
          const auto& title = std::get<std::string>(*call.arguments());
          const int length = MultiByteToWideChar(CP_UTF8, 0, title.c_str(), -1, nullptr, 0);
          std::wstring wide(length, L'\0');
          MultiByteToWideChar(CP_UTF8, 0, title.c_str(), -1, wide.data(), length);
          SetWindowTextW(GetHandle(), wide.c_str());
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  title_channel_.reset();
  saved_login_channel_.reset();
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
