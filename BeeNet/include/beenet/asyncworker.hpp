#ifndef BEE_ASYNC_WORKER_HPP_INCLUDED
#define BEE_ASYNC_WORKER_HPP_INCLUDED

#include <cassert>
#include <cstring>
#include <memory>
#include <functional>
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>

namespace bee {
namespace net {

class AsyncBeeWorker {
public:
  static AsyncBeeWorker * Create() {
    static std::mutex global_instance_mutex;
    static std::unique_ptr<AsyncBeeWorker> global_instance;
    std::lock_guard<std::mutex> lck(global_instance_mutex);
    if (!global_instance) {
      std::unique_ptr<AsyncBeeWorker> tmp(new AsyncBeeWorker);
      std::thread worker(event_worker_process, tmp.get());
      tmp->event_worker_thread_ = std::move(worker);
      global_instance = std::move(tmp);
    }
    return global_instance.get();
  }

  ~AsyncBeeWorker() {
    if (event_worker_thread_.joinable()) {
      PostNotify('X');
      event_worker_thread_.join();
    }
  }

  void PostNotify(char sig) {
    assert(sig > 0);
    {
      std::lock_guard<std::mutex> lck(event_mutex_);
      event_q_.emplace(sig);
    }
    event_cv_.notify_one();
  }

  void PostCmd(std::function<void()> &&fn) {
    {
      std::lock_guard<std::mutex> lck(event_mutex_);
      cmd_q_.emplace(std::move(fn));
      event_q_.emplace(0);
    }
    event_cv_.notify_one();
  }

private:
  AsyncBeeWorker() = default;

  static void event_worker_process(AsyncBeeWorker *notify) {
    //DEBUG("asynchronous worker started");
    for ( ;; ) {
      try {
        std::unique_lock<std::mutex> lck(notify->event_mutex_);
        while (notify->event_q_.empty()) {
          notify->event_cv_.wait(lck);
        }
        char sig = notify->event_q_.front();
        notify->event_q_.pop();
        if ('X' == sig) {
          //BEE_LOG_DEBUG("asynchronous worker stopped");
          return;
        } else if (0 == sig) {
          assert(!notify->cmd_q_.empty());
          auto callback = std::move(notify->cmd_q_.front());
          notify->cmd_q_.pop();
          lck.unlock();
          callback();
        } else if (sig < 0) { //EAGAIN or other errors
          //DEBUG("asynchronous worker stopped by error %d", sig);
          break;
        }
      } catch (std::exception const &e) {
        //ERROR("asynchronous execute exception, %s", e.what());
      } catch (...) {
        //ERROR("asynchronous execute exception, unknown error");
      }
    }
  }

private:
  std::thread event_worker_thread_;
  std::queue<char> event_q_;
  std::queue<std::function<void()>> cmd_q_;
  std::mutex event_mutex_;
  std::condition_variable event_cv_;
};

}}

#endif
