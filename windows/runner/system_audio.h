#ifndef RUNNER_SYSTEM_AUDIO_H_
#define RUNNER_SYSTEM_AUDIO_H_

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// "Что играет?" on Windows: what the default speakers play (WASAPI
// loopback), as 16 kHz mono 16-bit PCM, like the microphone and the Mac.
class SystemAudio {
 public:
  // Pieces of sound are announced to |window| with |message|; Take() then
  // hands them over on the window's (Flutter's) thread.
  SystemAudio(HWND window, UINT message);
  ~SystemAudio();

  // Empty once sound is coming, otherwise why it isn't.
  std::string Start();
  void Stop();

  // Everything captured since the last call.
  std::vector<uint8_t> Take();

 private:
  void Run(HANDLE ready, std::string* error);

  HWND window_;
  UINT message_;
  std::thread thread_;
  std::atomic<bool> running_{false};
  std::mutex mutex_;
  std::vector<uint8_t> pending_;
};

#endif  // RUNNER_SYSTEM_AUDIO_H_
