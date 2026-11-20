#include "system_audio.h"

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <mmreg.h>

#include <algorithm>
#include <cstdio>
#include <memory>

namespace {

// KSDATAFORMAT_SUBTYPE_IEEE_FLOAT, spelled out so no extra library is needed.
const GUID kFloatSubtype = {0x00000003, 0x0000, 0x0010,
                            {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};

constexpr int kRate = 16000;

template <class T>
void Release(T*& p) {
  if (p) {
    p->Release();
    p = nullptr;
  }
}

std::string Hr(const char* what, HRESULT hr) {
  char buf[64];
  snprintf(buf, sizeof(buf), "%s (0x%08lx)", what, static_cast<unsigned long>(hr));
  return buf;
}

}  // namespace

SystemAudio::SystemAudio(HWND window, UINT message)
    : window_(window), message_(message) {}

SystemAudio::~SystemAudio() { Stop(); }

std::string SystemAudio::Start() {
  Stop();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    pending_.clear();
  }
  running_ = true;
  HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
  auto error = std::make_shared<std::string>();
  thread_ = std::thread([this, ready, error] { Run(ready, error.get()); });
  if (WaitForSingleObject(ready, 5000) != WAIT_OBJECT_0) {
    CloseHandle(ready);
    Stop();
    return "timeout";
  }
  CloseHandle(ready);
  if (!error->empty()) {
    Stop();
    return *error;
  }
  return "";
}

void SystemAudio::Stop() {
  running_ = false;
  if (thread_.joinable()) thread_.join();
}

std::vector<uint8_t> SystemAudio::Take() {
  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<uint8_t> out;
  out.swap(pending_);
  return out;
}

void SystemAudio::Run(HANDLE ready, std::string* error) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool com = SUCCEEDED(hr);
  IMMDeviceEnumerator* devices = nullptr;
  IMMDevice* speakers = nullptr;
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  WAVEFORMATEX* format = nullptr;

  auto fail = [&](const std::string& why) {
    *error = why;
    SetEvent(ready);
  };

  do {
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          __uuidof(IMMDeviceEnumerator),
                          reinterpret_cast<void**>(&devices));
    if (FAILED(hr)) { fail(Hr("no audio devices", hr)); break; }
    hr = devices->GetDefaultAudioEndpoint(eRender, eConsole, &speakers);
    if (FAILED(hr)) { fail(Hr("no speakers", hr)); break; }
    hr = speakers->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                            reinterpret_cast<void**>(&client));
    if (FAILED(hr)) { fail(Hr("speakers busy", hr)); break; }
    hr = client->GetMixFormat(&format);
    if (FAILED(hr)) { fail(Hr("no format", hr)); break; }
    // Loopback: what goes to the speakers, read back as if recorded.
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                            10000000, 0, format, nullptr);
    if (FAILED(hr)) { fail(Hr("loopback refused", hr)); break; }
    hr = client->GetService(__uuidof(IAudioCaptureClient),
                            reinterpret_cast<void**>(&capture));
    if (FAILED(hr)) { fail(Hr("no capture", hr)); break; }

    bool is_float = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
    if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
      auto* ext = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format);
      is_float = IsEqualGUID(ext->SubFormat, kFloatSubtype) != FALSE;
    }
    const int channels = std::max<int>(1, format->nChannels);
    const int bits = format->wBitsPerSample;
    const int frame_bytes = format->nBlockAlign;
    const double step = static_cast<double>(format->nSamplesPerSec) / kRate;

    hr = client->Start();
    if (FAILED(hr)) { fail(Hr("start failed", hr)); break; }
    SetEvent(ready);

    // Down to 16 kHz by averaging what falls into each output sample: a
    // plain low-pass, enough for a fingerprint.
    double acc = 0, count = 0, phase = 0;
    std::vector<int16_t> out;
    while (running_) {
      Sleep(20);
      UINT32 packet = 0;
      while (running_ && SUCCEEDED(capture->GetNextPacketSize(&packet)) && packet > 0) {
        BYTE* data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
        const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
        for (UINT32 f = 0; f < frames; f++) {
          double v = 0;
          if (!silent) {
            const BYTE* frame = data + static_cast<size_t>(f) * frame_bytes;
            for (int c = 0; c < channels; c++) {
              if (is_float) {
                v += reinterpret_cast<const float*>(frame)[c];
              } else if (bits == 16) {
                v += reinterpret_cast<const int16_t*>(frame)[c] / 32768.0;
              } else if (bits == 24) {
                const BYTE* s = frame + c * 3;
                int32_t x = (s[0] << 8) | (s[1] << 16) | (s[2] << 24);
                v += x / 2147483648.0;
              } else if (bits == 32) {
                v += reinterpret_cast<const int32_t*>(frame)[c] / 2147483648.0;
              }
            }
            v /= channels;
          }
          acc += v;
          count += 1;
          phase += 1;
          if (phase >= step) {
            phase -= step;
            const double s = std::clamp(acc / count, -1.0, 1.0);
            out.push_back(static_cast<int16_t>(s * 32767));
            acc = 0;
            count = 0;
          }
        }
        capture->ReleaseBuffer(frames);
      }
      if (!out.empty()) {
        {
          std::lock_guard<std::mutex> lock(mutex_);
          const auto* b = reinterpret_cast<const uint8_t*>(out.data());
          pending_.insert(pending_.end(), b, b + out.size() * 2);
        }
        out.clear();
        PostMessage(window_, message_, 0, 0);
      }
    }
    client->Stop();
  } while (false);

  if (format) CoTaskMemFree(format);
  Release(capture);
  Release(client);
  Release(speakers);
  Release(devices);
  if (com) CoUninitialize();
}
