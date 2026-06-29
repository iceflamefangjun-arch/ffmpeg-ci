#ifndef BEE_AVPLAYER_H_INCLUDED
#define BEE_AVPLAYER_H_INCLUDED

#ifdef __cplusplus
extern "C"  {
#endif
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libswscale/swscale.h"
#include "libavutil/imgutils.h"
#include "libavutil/opt.h"
#include "libavutil/fifo.h"
#include "libavutil/time.h"
#include "libavutil/audio_fifo.h"
#include "libavutil/samplefmt.h"
#include "libavutil/channel_layout.h"
#include "libswresample/swresample.h"
//#include "libavfilter/avfilter.h"
//#include "libavfilter/buffersink.h"
//#include "libavfilter/buffersrc.h"
#ifdef __cplusplus
}
#endif

#include <memory>
#include <string>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <functional>

#define MAX_QUEUED_PACKETS 32
#define FIFO_BUFFER_GROW_NUM 32

namespace bee {
namespace net {

class BeeAVPlayer {
public:
  template<typename T=BeeAVPlayer, typename... Args,
    typename = typename std::enable_if<std::is_base_of<BeeAVPlayer,T>::value>::type>
  static std::shared_ptr<T> Create(Args... args) {
    auto player = std::make_shared<T>(std::forward<Args>(args)...);
    player->self_ = player;
    return player;
  }

  bool open(const char* url, const char* format=nullptr, bool is_live=false);
  void close(); //open之后必须调用close才能释放资源，不等待后台线程结束

  void Shutdown(); //close并等待后台线程结束

  const char * URL() const { return source_.url.c_str(); }

  //为最后一个open操作的对象设置options
  void SetOption(const std::string& key, const std::string& value);
  void SetOption(const std::string& key, const int value);

  bool IsPlaying() const;
  bool IsPlayEnd() const;

  bool HasVideo() const;
  bool HasAudio() const;

  float GetStartPlayTime() const;
  float GetTotalPlayTime() const;

  void play();
  void seek(float time_in_sec);
  void pause();

  void onerror(std::function<void(const char*, int, const char*, const char*)>&& cb);
  void onstart(std::function<void()>&& cb);
  void onplay(std::function<void()>&& cb);
  void onvideo(std::function<void(AVFrame*)>&& cb);
  void onaudio(std::function<void(AVFrame*)>&& cb);
  void onpause(std::function<void()>&& cb);
  void onstop(std::function<void()>&& cb);

protected:
  BeeAVPlayer() = default;
  virtual ~BeeAVPlayer();

  const AVCodecParameters* GetVideoCodecParams() const;
  const AVCodecParameters* GetAudioCodecParams() const;

  float GetFrameTime(AVFrame* frame) const;

private:
  BeeAVPlayer(BeeAVPlayer&) = delete;
  const BeeAVPlayer& operator =(const BeeAVPlayer&) = delete;

  void SetLastError(int lineno, const char* prefix, int av_err);
  void SetLastError(int lineno, const char* prefix, const char* fmt, ...);

  void PlayerThreadLoop();
  void DecodeThreadLoop();

  AVCodecContext* CreateDecoderContext(AVStream* stream);
  int DecodePacketQueuePut(AVPacket* pkt);
  AVPacket* DecodePacketQueueGet();
  void DecodePacketQueueClear();

protected:
  virtual void on_error(const char* file, int lineno,
                        const char* prefix, const char* err);
  virtual void on_start();
  virtual void on_play();
  virtual void on_video(AVFrame* frame);
  virtual void on_audio(AVFrame* frame);
  virtual void on_pause();
  virtual void on_stop();

private:
  struct {
    std::string url;
#if LIBAVUTIL_VERSION_MAJOR < 57
    AVInputFormat* format = nullptr;
#else
    const AVInputFormat* format = nullptr;
#endif
    AVDictionary* options = nullptr;
  } source_;

  std::function<void(const char*, int, const char*, const char*)> on_error_;
  std::function<void()> on_start_;
  std::function<void()> on_play_;
  std::function<void(AVFrame*)> on_video_;
  std::function<void(AVFrame*)> on_audio_;
  std::function<void()> on_pause_;
  std::function<void()> on_stop_;

  std::thread decode_thread_;
  std::thread player_thread_;

  struct FFmpegDeleter {
    void operator()(AVFormatContext* p) { avformat_close_input(&p); }
    void operator()(AVCodecContext* p) { avcodec_free_context(&p); }
    void operator()(AVFrame* p) { av_frame_free(&p); }
    void operator()(AVPacket* p) { av_packet_free(&p); }
    void operator()(SwrContext* p) { swr_free(&p); }
#if LIBAVUTIL_VERSION_MAJOR < 57
    void operator()(AVFifoBuffer* p) { av_fifo_freep(&p); }
#else
    void operator()(AVFifo* p) { av_fifo_freep2(&p); }
#endif
    //void operator()(AVFilterGraph* p) { avfilter_graph_free(&p); }
    //void operator()(AVFilterContext* p) { avfilter_free(p); }
  };

  using AutoFormatContext = std::unique_ptr<AVFormatContext, FFmpegDeleter>;
  using AutoCodecContext = std::unique_ptr<AVCodecContext, FFmpegDeleter>;
  using AutoFrame = std::unique_ptr<AVFrame, FFmpegDeleter>;
  using AutoPacket = std::unique_ptr<AVPacket, FFmpegDeleter>;
  using AutoSwrContext = std::unique_ptr<SwrContext, FFmpegDeleter>;
#if LIBAVUTIL_VERSION_MAJOR < 57
  using AutoFifoBuffer = std::unique_ptr<AVFifoBuffer, FFmpegDeleter>;
#else
  using AutoFifoBuffer = std::unique_ptr<AVFifo, FFmpegDeleter>;
#endif
  //using AutoFilterGraph = std::unique_ptr<AVFilterGraph, FFmpegDeleter>;
  //using AutoFilterContext = std::unique_ptr<AVFilterContext, FFmpegDeleter>;

  enum : int { AV_AUDIO=0, AV_VIDEO, AV_STREAMS_NB };

  AutoFormatContext fmt_ctx_;
  AVStream* streams_[AV_STREAMS_NB];
  AutoCodecContext decoder_[AV_STREAMS_NB];

  AutoFifoBuffer queued_packets_;
  std::mutex decode_queue_mutex_;
  std::condition_variable decode_queue_empty_;
  std::condition_variable decode_queue_full_or_eof_;

  enum : int32_t {
    S_INIT      = 0x00,
    S_OPENED    = 0x01,
    S_PLAYING   = 0x02,
    S_TERMINATE = 0x04,
    S_COMPLETED = 0x10,
    S_STOPPED   = 0x20,
    S_ERROR     = 0x80,
  };
  int32_t state_ = S_INIT;

  bool live_streaming_ = false;
  bool time_sync_needed_ = true;
  bool play_reset_needed_ = false;

  int64_t duration_ = AV_NOPTS_VALUE;
  int64_t start_time_ = AV_NOPTS_VALUE;
  int64_t seek_to_time_ = AV_NOPTS_VALUE;

  std::weak_ptr<BeeAVPlayer> self_;
};

} //namespace net
} //namespace bee

#endif //BEE_AVPLAYER_H_INCLUDED
