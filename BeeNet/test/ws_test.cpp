#include <cstdio>
#include <chrono>
#include <thread>
#include <functional>
#include "beenet/interface.hpp"

class WSClient final : public bee::net::AsyncBeeStream {
public:
  WSClient() = default;
  ~WSClient() = default;

  void onopen(std::function<void()> &&onopen) noexcept {
    onopen_ = std::move(onopen);
  }

  void onclose(std::function<void()> &&onclose) noexcept {
    onclose_ = std::move(onclose);
  }

  void onerror(std::function<void(int)> &&onerror) noexcept {
    onerror_ = std::move(onerror);
  }

  void onmessage(std::function<void(char const *, size_t)> &&onmessage) noexcept {
    onmessage_ = std::move(onmessage);
  }

  bool ready() const {
    return (fd() > 0);
  }

private:
  void on_open() {
    if (onopen_) onopen_();
    read(1024);
  }

  size_t on_recv(void const *buffer, size_t length) {
    if (nullptr == buffer || 0 == length) {
      close();
      return 0;
    }
    if (onmessage_) onmessage_(static_cast<char const *>(buffer), length);
    read(1024);
    return length;
  }

  void on_error(int error) {
    if (onerror_) onerror_(error);
    close();
  }

  void on_close(int error) {
    if (onclose_) onclose_();
  }

  std::function<void()> onopen_;
  std::function<void()> onclose_;
  std::function<void(int)> onerror_;
  std::function<void(char const *, size_t)> onmessage_;
};

int main(int argc, char *argv[])
{
  bee_logger_init(9, nullptr);
  //bee_env_init(nullptr);

  auto ws = bee::net::AsyncBeeStream::Create<WSClient>();
  if (ws) {
    ws->open("ws://10.19.117.38:88/ws_echo", "{\"timeout\":5}");

    ws->onopen([=]()->void {
      fprintf(stderr, "websocket open success\n");
      ws->send("hello", sizeof("hello") - 1);
    });

    ws->onerror([=](int error)->void {
      if (error < -65536) {
        int tmp = -error;
        fprintf(stderr, "websocket error (%.*s)\n", 4, (const char *)&tmp);
      } else {
        fprintf(stderr, "websocket error (%d)\n", error);
      }
    });

    ws->onclose([=]()->void {
      fprintf(stderr, "websocket close\n");
    });

    ws->onmessage([=](const char *msg, size_t len)->void {
      fprintf(stderr, "websocket: %.*s\n", static_cast<int>(len), msg);
    });

    for (int i = 0; i < 100; ++i) {
      std::this_thread::sleep_for(std::chrono::seconds(3));
      if (ws->ready() > 0) ws->send("hello", sizeof("hello") - 1);
    }
  }

  bee_env_cleanup();
  return 0;
}
