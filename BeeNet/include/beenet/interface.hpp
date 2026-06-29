#ifndef BEE_INTERFACE_HPP_INCLUDED
#define BEE_INTERFACE_HPP_INCLUDED

#include "interface.h"
#include <cassert>
#include <cstring>
#include <cerrno>
#include <memory>
#include <atomic>

namespace bee {
namespace net {

class AsyncBeeStream {
private:
  class WeakSelfRefer {
  public:
    explicit WeakSelfRefer(const std::shared_ptr<AsyncBeeStream>& sp)
      : ref_count_(1), weak_ptr_(sp) {}
    WeakSelfRefer* AddRef() {
      ref_count_.fetch_add(1, std::memory_order_relaxed);
      return this;
    }
    void Release() {
      if (ref_count_.fetch_sub(1, std::memory_order_relaxed) == 1)
        delete this;
    }
    std::shared_ptr<AsyncBeeStream> GetSharedPtr() {
      return weak_ptr_.lock();
    }
  private:
    WeakSelfRefer() = delete;
    WeakSelfRefer(const WeakSelfRefer&) = delete;
    WeakSelfRefer& operator =(const WeakSelfRefer&) = delete;
    ~WeakSelfRefer() = default;
    std::atomic<int> ref_count_;
    std::weak_ptr<AsyncBeeStream> weak_ptr_;
  };

  WeakSelfRefer* weak_self_;

  int fd_;
  std::atomic<bool> close_invoking_, open_invoking_;

  static void close_callback(int error, void* userp) {
    auto ref = reinterpret_cast<WeakSelfRefer*>(userp);
    auto stream = ref->GetSharedPtr(); ref->Release();
    if (!stream || !stream->self_) return;
    if (stream->open_invoking_.load(std::memory_order_relaxed)) return;
    if (bool exp = true; stream->close_invoking_.compare_exchange_strong(
        exp, false, std::memory_order_relaxed)) {
      stream->on_close(error);
      stream->fd_ = -65535;
      stream->self_.reset();
    }
  }

  static void send_callback(int error, void* userp) {
    auto ref = reinterpret_cast<WeakSelfRefer*>(userp);
    auto stream = ref->GetSharedPtr(); ref->Release();
    if (!stream || !stream->self_) return;
    if (error < 0) {
      return stream->on_error(error);
    } else {
      return stream->on_sent();
    }
  }

  static void seek_callback(off_t offset, void* userp) {
    auto ref = reinterpret_cast<WeakSelfRefer*>(userp);
    auto stream = ref->GetSharedPtr(); ref->Release();
    if (!stream || !stream->self_) return;
    if (offset < 0) {
      return stream->on_error(static_cast<int>(offset));
    } else {
      return stream->on_seek(offset);
    }
  }

  static void stat_callback(const void* buffer, int length, void* userp) {
    auto ref = reinterpret_cast<WeakSelfRefer*>(userp);
    auto stream = ref->GetSharedPtr(); ref->Release();
    if (!stream || !stream->self_) return;
    if (nullptr == buffer && length < 0) {
      return stream->on_error(length);
    } else if (length > 0) {
      return stream->on_stat(buffer, length);
    }
  }

  static size_t read_callback(const void* buffer, size_t length, void* userp) {
    auto ref = reinterpret_cast<WeakSelfRefer*>(userp);
    auto stream = ref->GetSharedPtr(); ref->Release();
    if (!stream || !stream->self_) return 0;
    if (nullptr == buffer && length != 0) {
      stream->on_error(static_cast<int>(length));
      return 0;
    }
    assert(nullptr == buffer || length > 0);
    return stream->on_recv(buffer, length);
  }

  static void open_callback(int fd_or_err, void* userp) {
    auto ref = reinterpret_cast<WeakSelfRefer*>(userp);
    auto stream = ref->GetSharedPtr(); ref->Release();
    if (!stream || !stream->self_) return;
    assert(fd_or_err != 0);
    assert(stream->open_invoking_.load(std::memory_order_relaxed));
    if (fd_or_err > 0) {
      assert(stream->fd_ < 0);
      stream->fd_ = fd_or_err;
      if (stream->close_invoking_.load(std::memory_order_relaxed))
        bee_close_async(fd_or_err, close_callback, ref->AddRef());
      else stream->on_open();
    }
    stream->open_invoking_.store(false, std::memory_order_relaxed);
    if (fd_or_err > 0) return;
    if (bool exp = true; stream->close_invoking_.compare_exchange_strong(
        exp, false, std::memory_order_relaxed)) {
      stream->on_close(fd_or_err);
      stream->fd_ = -65535;
      stream->self_.reset();
    } else stream->on_error(fd_or_err);
  }

public:
  template<typename T, typename... Args,
    typename = typename std::enable_if<std::is_base_of<AsyncBeeStream,T>::value>::type>
  static std::shared_ptr<T> Create(Args... args) {
    auto stream = std::make_shared<T>(std::forward<Args>(args)...);
    stream->weak_self_ = new WeakSelfRefer(stream);
    return stream;
  }

  void open(const char* url, const char* json_args) {
    assert(!self_ && fd_ < 0);
    assert(!close_invoking_.load(std::memory_order_relaxed));
    if (bool exp = false; open_invoking_.compare_exchange_strong(
        exp, true, std::memory_order_relaxed)) {
      self_ = weak_self_->GetSharedPtr();
      bee_open_async(url, json_args, open_callback, weak_self_->AddRef());
    }
  }

  void read(size_t expect_length) {
    bee_read_async(fd_, expect_length, read_callback, weak_self_->AddRef());
  }

  void stat() {
    bee_stat_async(fd_, stat_callback, weak_self_->AddRef());
  }

  void seek(off_t offset, int whence) {
    bee_seek_async(fd_, offset, whence, seek_callback, weak_self_->AddRef());
  }

  void send(const char* message, size_t msglen) {
    bee_send_async(fd_, message, msglen, send_callback, weak_self_->AddRef());
  }

  void close() {
    if (bool exp = false; close_invoking_.compare_exchange_strong(
        exp, true, std::memory_order_relaxed)) {
      bee_close_async(fd_, close_callback, weak_self_->AddRef());
    }
  }

protected:
  AsyncBeeStream() : fd_(-65535), close_invoking_(false), open_invoking_(false) {}
  virtual ~AsyncBeeStream() { weak_self_->Release(); }

  int fd() const { return fd_; }

  virtual void on_open() = 0;
  virtual size_t on_recv(const void *buffer, size_t length) = 0;
  virtual void on_stat(const void *buffer, int length) {}
  virtual void on_seek(off_t offset) {}
  virtual void on_sent() {}
  virtual void on_error(int error) {}
  virtual void on_close(int error) {}

  std::shared_ptr<AsyncBeeStream> self_;

private:
  AsyncBeeStream(const AsyncBeeStream&) = delete;
  AsyncBeeStream& operator =(const AsyncBeeStream&) = delete;
};

}}

#endif
