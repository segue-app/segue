#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

namespace {
// Posted by the capture thread: sound is waiting in SystemAudio.
constexpr UINT kAudioMessage = WM_APP + 0x5E6;
}  // namespace

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
  SetUpSystemAudio();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetUpSystemAudio() {
  auto* messenger = flutter_controller_->engine()->messenger();
  system_audio_ = std::make_unique<SystemAudio>(GetHandle(), kAudioMessage);
  audio_events_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "fm.segue/sysaudio/pcm",
      &flutter::StandardMethodCodec::GetInstance());
  audio_events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            audio_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            audio_sink_ = nullptr;
            return nullptr;
          }));
  audio_methods_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "fm.segue/sysaudio", &flutter::StandardMethodCodec::GetInstance());
  audio_methods_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& name = call.method_name();
        if (name == "supported") {
          result->Success(flutter::EncodableValue(true));
        } else if (name == "start") {
          const std::string error = system_audio_->Start();
          if (error.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(error));
          }
        } else if (name == "stop") {
          system_audio_->Stop();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::OnDestroy() {
  if (system_audio_) system_audio_->Stop();
  audio_sink_ = nullptr;
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
    case kAudioMessage:
      if (system_audio_) {
        auto pcm = system_audio_->Take();
        if (audio_sink_ && !pcm.empty()) {
          audio_sink_->Success(flutter::EncodableValue(pcm));
        }
      }
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
