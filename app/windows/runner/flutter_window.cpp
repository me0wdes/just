#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <appmodel.h>
#include <winrt/Windows.UI.Notifications.h>

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
  platform_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "day/platform",
      &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "feedbackAllowed") {
      QUERY_USER_NOTIFICATION_STATE state;
      // Tones answer the user's own clicks, so only presentation mode mutes
      // them. QUNS_BUSY also covers any full-screen window, including Just
      // itself, which silenced sounds at random.
      const bool allowed = FAILED(SHQueryUserNotificationState(&state)) ||
                           state != QUNS_PRESENTATION_MODE;
      result->Success(flutter::EncodableValue(allowed));
    } else if (call.method_name() == "hasPackageIdentity") {
      UINT32 length = 0;
      const auto status = GetCurrentPackageFullName(&length, nullptr);
      result->Success(flutter::EncodableValue(status == ERROR_INSUFFICIENT_BUFFER));
    } else if(call.method_name() == "notificationSetting") {
      using winrt::Windows::UI::Notifications::ToastNotificationManager;
      // Packaged builds have an identity; the installer build is known to
      // Windows by the AppUserModelID the notification plugin registers.
      int setting = -1;
      try {
        setting = static_cast<int>(ToastNotificationManager::CreateToastNotifier().Setting());
      } catch(const winrt::hresult_error&) {
        try {
          setting = static_cast<int>(ToastNotificationManager::CreateToastNotifier(L"ClaudeWork.Day").Setting());
        } catch(const winrt::hresult_error&) {}
      }
      result->Success(flutter::EncodableValue(setting));
    } else { result->NotImplemented(); }
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
  platform_channel_.reset();
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
