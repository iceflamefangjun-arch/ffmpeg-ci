#include "BeeAVPlayer.h"
#include <chrono>
#include <cstdarg>
#include <cassert>

namespace bee {
namespace net {

class autorelease final {
public:
  explicit autorelease(std::function<void()>&& cb) {
    release_func_ = std::move(cb);
  }
  ~autorelease() {
    release_func_();
  }
private:
  autorelease() = delete;
  autorelease(const autorelease&) = delete;
  autorelease& operator =(const autorelease&) = delete;
  std::function<void()> release_func_;
};

BeeAVPlayer::~BeeAVPlayer()
{
  assert(!player_thread_.joinable());
  assert(!queued_packets_);
  assert(!decoder_[AV_VIDEO]);
  assert(!decoder_[AV_AUDIO]);
  assert(!fmt_ctx_);
}

bool BeeAVPlayer::open(const char* url, const char* format, bool is_live)
{
  assert(url != nullptr);

  if ((state_ & 0x0f) != S_INIT) {
    SetLastError(__LINE__, "open", "(%s) open already invoked", url);
    return false;
  }

  source_.url.assign(url);
  source_.format = nullptr;
  //source_.options = nullptr;
  av_dict_free(&source_.options);

  for (int i = 0; i < AV_STREAMS_NB; ++i) {
    assert(!decoder_[i]);
    streams_[i] = nullptr;
    decoder_[i].reset();
  }

  start_time_ = AV_NOPTS_VALUE;
  duration_ = AV_NOPTS_VALUE;

  live_streaming_ = is_live;
  time_sync_needed_ = true;
  play_reset_needed_ = false;
  seek_to_time_ = AV_NOPTS_VALUE;

  //fmt_ctx_.reset();
  assert(!fmt_ctx_);

  if (nullptr != format) {
    source_.format = av_find_input_format(format);
    if (nullptr == source_.format) {
      SetLastError(__LINE__, "av_find_input_format", "%s not found", format);
      return false;
    }
  }

  /* reduce the latency by flushing out packets immediately for av_read_frame */
  if (live_streaming_) av_dict_set(&source_.options, "avioflags", "direct", 0);
  av_dict_set(&source_.options, "fflags", "flush_packets", 0);
  av_dict_set(&source_.options, "http_persistent", "0", 0);

  state_ = S_OPENED;
  return true;
}

void BeeAVPlayer::SetOption(const std::string& key, const std::string& value)
{
  assert(state_ == S_OPENED);
  av_dict_set(&source_.options, key.c_str(), value.c_str(), 0);
}

void BeeAVPlayer::SetOption(const std::string& key, const int value)
{
  assert(state_ == S_OPENED);
  av_dict_set_int(&source_.options, key.c_str(), value, 0);
}

void BeeAVPlayer::play()
{
  if (S_INIT == (state_ & 0x0f)) {
    SetLastError(__LINE__, "play", "player was not opened correctly");
  } else if (!player_thread_.joinable()) {
    auto player_thread_wrapped = [](std::shared_ptr<BeeAVPlayer> self) {
      self->PlayerThreadLoop();
    };
    player_thread_ = std::thread(player_thread_wrapped, self_.lock());
    state_ |= S_PLAYING;
  } else {
    {
      std::lock_guard<std::mutex> lock(decode_queue_mutex_);
      if ((state_ & S_PLAYING) == 0) state_ |= S_PLAYING;
    }
    decode_queue_empty_.notify_all();
  }
}

void BeeAVPlayer::seek(float time_in_sec)
{
  if (S_INIT == (state_ & 0x0f)) {
    SetLastError(__LINE__, "seek", "player was not opened correctly");
  } else {
    {
      std::lock_guard<std::mutex> lock(decode_queue_mutex_);
      if ((state_ & S_COMPLETED) != 0) state_ &= ~S_COMPLETED;
      seek_to_time_ = time_in_sec * AV_TIME_BASE;
    }
    decode_queue_full_or_eof_.notify_all();
  }
}

void BeeAVPlayer::pause()
{
  if (S_INIT == (state_ & 0x0f)) {
    SetLastError(__LINE__, "pause", "player was not opened correctly");
  } else {
    {
      std::lock_guard<std::mutex> lock(decode_queue_mutex_);
      if ((state_ & S_PLAYING) != 0) state_ &= ~S_PLAYING;
    }
    decode_queue_empty_.notify_all();
  }
}

void BeeAVPlayer::close()
{
  {
    std::lock_guard<std::mutex> lock(decode_queue_mutex_);
    assert(0 == (state_ & S_TERMINATE));
    state_ |= S_TERMINATE;
  }
  if (player_thread_.joinable()) {
    decode_queue_full_or_eof_.notify_all();
    player_thread_.detach();
    //player_thread_.join();
  } else /*if ((state_ & 0x0f) != S_INIT)*/ {
    assert(!fmt_ctx_);
    assert(!queued_packets_);
    assert(!decoder_[AV_VIDEO]);
    assert(!decoder_[AV_AUDIO]);
#if 0
    assert(!swr_ctx_);
    assert(!filter_graph_);
#endif
    av_dict_free(&source_.options);
    state_ = S_INIT;
  }
}

void BeeAVPlayer::Shutdown()
{
  {
    std::lock_guard<std::mutex> lock(decode_queue_mutex_);
    state_ |= S_TERMINATE;
  }
  if (player_thread_.joinable()) {
    decode_queue_full_or_eof_.notify_all();
    player_thread_.join();
  } else if ((state_ & 0x0f) != S_INIT) {
    assert(!fmt_ctx_);
    assert(!queued_packets_);
    assert(!decoder_[AV_VIDEO]);
    assert(!decoder_[AV_AUDIO]);
#if 0
    assert(!swr_ctx_);
    assert(!filter_graph_);
#endif
    av_dict_free(&source_.options);
    state_ = S_INIT;
  }
}

#if 0
void BeeAVPlayer::oninit(std::function<void()>&& cb)
{
  assert(!on_init_);
  on_init_ = std::move(cb);
}

void BeeAVPlayer::on_init()
{
  if (on_init_) on_init_();
}
#endif

void BeeAVPlayer::onstart(std::function<void()>&& cb)
{
  assert(!on_start_);
  on_start_ = std::move(cb);
}

void BeeAVPlayer::on_start()
{
  if (on_start_) on_start_();
}

void BeeAVPlayer::onplay(std::function<void()>&& cb)
{
  assert(!on_play_);
  on_play_ = std::move(cb);
}

void BeeAVPlayer::on_play()
{
  if (on_play_) on_play_();
}

void BeeAVPlayer::onvideo(std::function<void(AVFrame*)>&& cb)
{
  assert(!on_video_);
  on_video_ = std::move(cb);
}

void BeeAVPlayer::on_video(AVFrame* frame)
{
  if (on_video_) on_video_(frame);
}

void BeeAVPlayer::onaudio(std::function<void(AVFrame*)>&& cb)
{
  assert(!on_audio_);
  on_audio_ = std::move(cb);
}

void BeeAVPlayer::on_audio(AVFrame* frame)
{
  if (on_audio_) on_audio_(frame);
}

void BeeAVPlayer::onpause(std::function<void()>&& cb)
{
  assert(!on_pause_);
  on_pause_ = std::move(cb);
}

void BeeAVPlayer::on_pause()
{
  if (on_pause_) on_pause_();
}

void BeeAVPlayer::onstop(std::function<void()>&& cb)
{
  assert(!on_stop_);
  on_stop_ = std::move(cb);
}

void BeeAVPlayer::on_stop()
{
  if (on_stop_) on_stop_();
}

void BeeAVPlayer::onerror(
  std::function<void(const char*, int, const char*, const char*)>&& cb)
{
  assert(!on_error_);
  on_error_ = std::move(cb);
}

void BeeAVPlayer::on_error(
  const char* file, int line, const char* prefix, const char* err)
{
  if (on_error_) on_error_(file, line, prefix, err);
}

void BeeAVPlayer::SetLastError(int lineno, const char* prefix, int av_err)
{
  char errstr[AV_ERROR_MAX_STRING_SIZE];
  av_strerror(av_err, errstr, sizeof(errstr));
  on_error(__FILE__, lineno, prefix, errstr);
}

void BeeAVPlayer::SetLastError(int lineno, const char* prefix, const char* fmt, ...)
{
  char errstr[1024];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(errstr, sizeof(errstr), fmt, ap);
  va_end(ap);
  if (n >= (int)sizeof(errstr)) errstr[sizeof(errstr)-1] = '\0';
  on_error(__FILE__, lineno, prefix, errstr);
}

const AVCodecParameters* BeeAVPlayer::GetVideoCodecParams() const
{
  assert((state_ & 0x0f) != 0);
  if (nullptr == streams_[AV_VIDEO]) return nullptr;
  return streams_[AV_VIDEO]->codecpar;
}

const AVCodecParameters* BeeAVPlayer::GetAudioCodecParams() const
{
  assert((state_ & 0x0f) != 0);
  if (nullptr == streams_[AV_AUDIO]) return nullptr;
  return streams_[AV_AUDIO]->codecpar;
}

bool BeeAVPlayer::IsPlaying() const
{
  return ((state_ & S_PLAYING) != 0);
}

bool BeeAVPlayer::IsPlayEnd() const
{
  return ((state_ & S_COMPLETED) != 0);
}

bool BeeAVPlayer::HasVideo() const
{
  return (streams_[AV_VIDEO] != nullptr);
}

bool BeeAVPlayer::HasAudio() const
{
  return (streams_[AV_AUDIO] != nullptr);
}

float BeeAVPlayer::GetStartPlayTime() const
{
  if (start_time_ == AV_NOPTS_VALUE) return 0.0f;
  return (static_cast<float>(start_time_) / AV_TIME_BASE);
}

float BeeAVPlayer::GetTotalPlayTime() const
{
  if (duration_ == AV_NOPTS_VALUE) return 0.0f;
  return (static_cast<float>(duration_) / AV_TIME_BASE);
}

float BeeAVPlayer::GetFrameTime(AVFrame* frame) const
{
  assert((state_ & 0x0f) != 0);
  float timestamp = std::numeric_limits<float>::lowest();
  AVStream* stream = nullptr;
  if (frame->width > 0 && frame->height > 0) {
    stream = streams_[AV_VIDEO];
  } else if (frame->nb_samples > 0 &&
#if LIBAVUTIL_VERSION_MAJOR < 57
      frame->channels > 0) {
#else
      av_channel_layout_check(&frame->ch_layout)) {
#endif
    stream = streams_[AV_AUDIO];
  }
  assert(stream != nullptr);
  timestamp = (float)av_rescale_q(frame->pts,
      stream->time_base, AV_TIME_BASE_Q) / AV_TIME_BASE;
  return timestamp;
}

AVCodecContext* BeeAVPlayer::CreateDecoderContext(AVStream* stream)
{
  const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);

  if (nullptr == codec) {
    SetLastError(__LINE__, "avcodec_find_decoder", "codec id (%d) not found",
                 stream->codecpar->codec_id);
    return nullptr;
  }

  AutoCodecContext decoder(avcodec_alloc_context3(codec));
  if (!decoder) {
    SetLastError(__LINE__, "avcodec_alloc_context3", AVERROR(ENOMEM));
    return nullptr;
  }

  int err = avcodec_parameters_to_context(decoder.get(), stream->codecpar);
  if (err < 0) {
    SetLastError(__LINE__, "avcodec_parameters_to_context", err);
    return nullptr;
  }

#if CONFIG_D3D11VA
# define AV_HWDEVICE_BUILTIN AV_HWDEVICE_TYPE_D3D11VA
#elif CONFIG_VIDEOTOOLBOX
# define AV_HWDEVICE_BUILTIN AV_HWDEVICE_TYPE_VIDEOTOOLBOX
#endif

#ifdef AV_HWDEVICE_BUILTIN
  if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
    for (int i = 0;; ++i) {
      const AVCodecHWConfig* config = avcodec_get_hw_config(codec, i);
      if (config == nullptr) break;
      if (config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX &&
          config->device_type == AV_HWDEVICE_BUILTIN) {
        AVBufferRef* hw_device_ctx = nullptr;
        err = av_hwdevice_ctx_create(&hw_device_ctx,
            AV_HWDEVICE_BUILTIN, nullptr, nullptr, 0);
        if (err < 0) {
          SetLastError(__LINE__, "av_hwdevice_ctx_create", err);
        } else {
          SetLastError(__LINE__, "avcodec_get_hw_config",
              "use %s as hardware decoder for %s",
              av_hwdevice_get_type_name(AV_HWDEVICE_BUILTIN), codec->name);
          decoder->hw_device_ctx = hw_device_ctx;
        }
        break;
      }
    }
  }
#endif
  //else if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
  //  if (0 == decoder->channel_layout && decoder->channels > 0) {
  //    decoder->channel_layout = av_get_default_channel_layout(decoder->channels);
  //  }
  //}

  err = avcodec_open2(decoder.get(), nullptr, nullptr);
  if (err < 0) {
    SetLastError(__LINE__, "avcodec_open2", err);
    return nullptr;
  }

  return decoder.release();
}

int BeeAVPlayer::DecodePacketQueuePut(AVPacket* pkt)
{
  std::unique_lock<std::mutex> lock(decode_queue_mutex_);
#if LIBAVUTIL_VERSION_MAJOR < 57
  assert(av_fifo_size(queued_packets_.get()) +
      av_fifo_space(queued_packets_.get()) < 4096);
#else
  assert(av_fifo_can_read(queued_packets_.get()) +
      av_fifo_can_write(queued_packets_.get()) < 1024);
#endif

  for (bool wakeup = false; ;) {
    assert(queued_packets_);
#if LIBAVUTIL_VERSION_MAJOR < 57
    if (av_fifo_size(queued_packets_.get()) < MAX_QUEUED_PACKETS * (int)sizeof(pkt)) break;
#else
    if (av_fifo_can_read(queued_packets_.get()) < MAX_QUEUED_PACKETS) break;
#endif
    if (wakeup) return 0;
    decode_queue_full_or_eof_.wait(lock);
    wakeup = true;
  }

#if LIBAVUTIL_VERSION_MAJOR < 57
  if (av_fifo_space(queued_packets_.get()) < (int)sizeof(pkt)) {
    int err = av_fifo_grow(queued_packets_.get(), 32 * (int)sizeof(pkt));
#else
  if (av_fifo_can_write(queued_packets_.get()) < 1) {
    int err = av_fifo_grow2(queued_packets_.get(), FIFO_BUFFER_GROW_NUM);
#endif
    if (err < 0) {
      lock.unlock();
#if LIBAVUTIL_VERSION_MAJOR < 57
      SetLastError(__LINE__, "av_fifo_grow", err);
#else
      SetLastError(__LINE__, "av_fifo_grow2", err);
#endif
      return -1;
    }
  }

  AVPacket* pkt_copy = av_packet_clone(pkt);
  if (nullptr == pkt_copy) {
    lock.unlock();
    SetLastError(__LINE__, "av_packet_clone", AVERROR(ENOMEM));
    return -1;
  }

#if LIBAVUTIL_VERSION_MAJOR < 57
  av_fifo_generic_write(queued_packets_.get(), &pkt_copy, sizeof(pkt_copy), nullptr);
#else
  av_fifo_write(queued_packets_.get(), &pkt_copy, 1);
#endif

  lock.unlock();
  decode_queue_empty_.notify_one();

  return 1;
}

AVPacket* BeeAVPlayer::DecodePacketQueueGet()
{
  AVPacket* pkt;
  std::unique_lock<std::mutex> lock(decode_queue_mutex_);

  for (bool wakeup = false;; ) {
    assert(queued_packets_);
    if ((state_ & S_PLAYING) != 0) {
#if LIBAVUTIL_VERSION_MAJOR < 57
      if (av_fifo_size(queued_packets_.get()) >= (int)sizeof(pkt)) {
#else
      if (av_fifo_can_read(queued_packets_.get()) > 0) {
#endif
        break;
      } else if ((state_ & S_COMPLETED) != 0) {
        state_ &= ~S_PLAYING;
        return nullptr;
      }
    }
    if (wakeup) return nullptr;
    decode_queue_empty_.wait(lock);
    time_sync_needed_ = true;
    wakeup = true;
  }

#if LIBAVUTIL_VERSION_MAJOR < 57
  av_fifo_generic_read(queued_packets_.get(), &pkt, sizeof(pkt), NULL);
#else
  av_fifo_read(queued_packets_.get(), &pkt, 1);
#endif
  if (nullptr == pkt) {
    //收到seek，需要重新计算起播时间
    time_sync_needed_ = true;
    play_reset_needed_ = true;
  }

  lock.unlock();

  decode_queue_full_or_eof_.notify_one();

  return pkt;
}

void BeeAVPlayer::DecodePacketQueueClear()
{
  std::unique_lock<std::mutex> lock(decode_queue_mutex_);
  assert(queued_packets_);

  AVPacket* pkt = nullptr;
#if LIBAVUTIL_VERSION_MAJOR < 57
  while (av_fifo_size(queued_packets_.get()) >= (int)sizeof(pkt)) {
    av_fifo_generic_read(queued_packets_.get(), &pkt, sizeof(pkt), nullptr);
#else
  while (av_fifo_can_read(queued_packets_.get()) > 0) {
    av_fifo_read(queued_packets_.get(), &pkt, 1);
#endif
    av_packet_free(&pkt);
  }

  //插入null，使得DecodePacketQueueGet的时候设置重新同步时钟
  assert(pkt == nullptr);
#if LIBAVUTIL_VERSION_MAJOR < 57
  av_fifo_generic_write(queued_packets_.get(), &pkt, sizeof(pkt), nullptr);
#else
  av_fifo_write(queued_packets_.get(), &pkt, 1);
#endif

  //play_reset_needed_ = true;

  lock.unlock();
  decode_queue_empty_.notify_one();
}

void BeeAVPlayer::PlayerThreadLoop()
{
  assert(!fmt_ctx_);
  int err;

#if __linux__
  pthread_setname_np(pthread_self(), "read_thread");
#elif __APPLE__
  //[[NSThread currentThread] setName:@"read_thread"];
  pthread_setname_np("read_thread");
#endif

  autorelease release_on_return([this]()->void {
    av_dict_free(&source_.options);
    {
      std::lock_guard<std::mutex> lock(decode_queue_mutex_);
      state_ |= S_TERMINATE;
    }
    if (decode_thread_.joinable()) {
      decode_queue_empty_.notify_all();
      decode_thread_.join();
    }
    if (queued_packets_) {
      AVPacket *pkt = nullptr;
#if LIBAVUTIL_VERSION_MAJOR < 57
      while (av_fifo_size(queued_packets_.get()) >= (int)sizeof(pkt)) {
        av_fifo_generic_read(queued_packets_.get(), &pkt, sizeof(pkt), nullptr);
#else
      while (av_fifo_can_read(queued_packets_.get()) > 0) {
        av_fifo_read(queued_packets_.get(), &pkt, 1);
#endif
        av_packet_free(&pkt);
      }
      queued_packets_.reset();
    }
    for (int i = 0; i < AV_STREAMS_NB; ++i) {
      decoder_[i].reset();
      //streams_[i] = nullptr;
    }
    fmt_ctx_.reset();
    state_ = (state_ & 0xf0) | S_STOPPED;
  });

  //on_init();

  AVFormatContext* fmt_ctx = nullptr;
  err = avformat_open_input(&fmt_ctx, source_.url.c_str(),
                            source_.format, &source_.options);
  if (err < 0) return SetLastError(__LINE__, "avformat_open_input", err);

  fmt_ctx_.reset(fmt_ctx);
  av_dict_free(&source_.options);

  /* retrieve stream information */
  err = avformat_find_stream_info(fmt_ctx_.get(), nullptr);
  if (err < 0) return SetLastError(__LINE__, "avformat_find_stream_info", err);

  for (unsigned i = 0; i < fmt_ctx_->nb_streams; i++) {
    AVStream* stream = fmt_ctx_->streams[i];
    stream->discard = AVDISCARD_ALL;
  }

  int video_stream_index = av_find_best_stream(
      fmt_ctx_.get(), AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
  if (video_stream_index >= 0) {
    streams_[AV_VIDEO] = fmt_ctx_->streams[video_stream_index];
    decoder_[AV_VIDEO].reset(CreateDecoderContext(streams_[AV_VIDEO]));
    streams_[AV_VIDEO]->discard = AVDISCARD_DEFAULT;
  }

  int audio_stream_index = av_find_best_stream(
      fmt_ctx_.get(), AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
  if (audio_stream_index >= 0) {
    streams_[AV_AUDIO] = fmt_ctx_->streams[audio_stream_index];
    decoder_[AV_AUDIO].reset(CreateDecoderContext(streams_[AV_AUDIO]));
    streams_[AV_AUDIO]->discard = AVDISCARD_DEFAULT;
  }

  if (streams_[AV_VIDEO] == nullptr && streams_[AV_AUDIO] == nullptr)
    return SetLastError(__LINE__, "av_find_best_stream", "no audio or video found");

#if LIBAVUTIL_VERSION_MAJOR < 57
  queued_packets_.reset(av_fifo_alloc_array(MAX_QUEUED_PACKETS, sizeof(AVPacket*)));
#else
  queued_packets_.reset(av_fifo_alloc2(MAX_QUEUED_PACKETS, sizeof(AVPacket*), 0));
#endif
  if (!queued_packets_)
#if LIBAVUTIL_VERSION_MAJOR < 57
    return SetLastError(__LINE__, "av_fifo_alloc_array", AVERROR(ENOMEM));
#else
    return SetLastError(__LINE__, "av_fifo_alloc2", AVERROR(ENOMEM));
#endif

  for (int i = 0; i < AV_STREAMS_NB; ++i) {
    if (nullptr == streams_[i]) continue;
    if (streams_[i]->start_time != AV_NOPTS_VALUE) {
      int64_t start_time = av_rescale_q(streams_[i]->start_time,
                                        streams_[i]->time_base,
                                        AV_TIME_BASE_Q);
      if (start_time_ == AV_NOPTS_VALUE || start_time_ > start_time)
        start_time_ = start_time;
    }
    if (streams_[i]->duration != AV_NOPTS_VALUE) {
      int64_t duration = av_rescale_q(streams_[i]->duration,
                                      streams_[i]->time_base,
                                      AV_TIME_BASE_Q);
      if (duration_ == AV_NOPTS_VALUE || duration_ < duration)
        duration_ = duration;
    }
  }
  if (start_time_ == AV_NOPTS_VALUE) start_time_ = fmt_ctx_->start_time;
  if (duration_ == AV_NOPTS_VALUE) duration_ = fmt_ctx_->duration;
  //if (streams_[AV_VIDEO]->nb_frames < 2) duration_ = AV_NOPTS_VALUE;

  decode_thread_ = std::thread(&BeeAVPlayer::DecodeThreadLoop, this);

  AutoPacket pkt(av_packet_alloc());
  if (!pkt) return SetLastError(__LINE__, "av_packet_alloc", AVERROR(ENOMEM));

  while ((state_ & S_TERMINATE) == 0) {
    if (seek_to_time_ != AV_NOPTS_VALUE) {
      int err = av_seek_frame(fmt_ctx_.get(), -1, seek_to_time_, AVSEEK_FLAG_BACKWARD);
      if (err < 0) return SetLastError(__LINE__, "av_seek_frame", err);
      DecodePacketQueueClear();
      seek_to_time_ = AV_NOPTS_VALUE;
    }

    err = av_read_frame(fmt_ctx_.get(), pkt.get());
    if (err == AVERROR_EOF) {
      std::unique_lock<std::mutex> lock(decode_queue_mutex_);
      state_ |= S_COMPLETED;
      if ((state_ & S_TERMINATE) == 0)
        decode_queue_full_or_eof_.wait(lock);
      continue;
    } else if (err == AVERROR(EAGAIN)) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
      continue;
    } else if (err < 0) {
      return SetLastError(__LINE__, "av_read_frame", err);
    }

#if 0
    if ((!HasVideo() || pkt->stream_index != streams_[AV_VIDEO]->index) &&
        (!HasAudio() || pkt->stream_index != streams_[AV_AUDIO]->index)) {
      av_packet_unref(pkt.get());
      continue;
    }
#endif

    while ((state_ & S_TERMINATE) == 0) {
      if (seek_to_time_ != AV_NOPTS_VALUE) break;
      err = DecodePacketQueuePut(pkt.get());
      if (err < 0) return;
      else if (err > 0) break;
      //else usleep(10000); //queue is full
    }

    av_packet_unref(pkt.get());
  }
}

void BeeAVPlayer::DecodeThreadLoop()
{
  int err;
  bool is_paused = false;

#if __linux__
  pthread_setname_np(pthread_self(), "decode_thread");
#elif __APPLE__
  //[[NSThread currentThread] setName:@"decode_thread"];
  pthread_setname_np("decode_thread");
#endif

  AutoFifoBuffer queued_frames[AV_STREAMS_NB];
  std::chrono::time_point<std::chrono::steady_clock> play_start_time;
  //最后一个播放音频帧结束的时间，避免播放不完整
  std::chrono::time_point<std::chrono::steady_clock> last_audio_time;
  int64_t sync_start_time = AV_NOPTS_VALUE;

  auto clear_queued_frames = +[](AutoFifoBuffer& queue)->void {
    AVFrame* frame = nullptr;
#if LIBAVUTIL_VERSION_MAJOR < 57
    while (av_fifo_size(queue.get()) >= (int)sizeof(frame)) {
      av_fifo_generic_read(queue.get(), &frame, sizeof(frame), nullptr);
#else
    while (av_fifo_can_read(queue.get()) > 0) {
      av_fifo_read(queue.get(), &frame, 1);
#endif
      av_frame_free(&frame);
    }
  };

  autorelease release_on_return([&,this]()->void {
    {
      std::lock_guard<std::mutex> lock(decode_queue_mutex_);
      state_ |= S_TERMINATE;
    }
    for (int i = 0; i < AV_STREAMS_NB; ++i) {
      if (!queued_frames[i]) continue;
      clear_queued_frames(queued_frames[i]);
      queued_frames[i].reset();
    }
    on_stop();
  });

#if LIBAVUTIL_VERSION_MAJOR < 57
  auto enqueue_frame = [this](AVFifoBuffer* list, AutoFrame& frame) {
    assert(list != nullptr && frame != nullptr);
    assert(av_fifo_size(list) + av_fifo_space(list) < 4096);
    if (av_fifo_space(list) < static_cast<int>(sizeof(AVFrame*))) {
      int err = av_fifo_grow(list, sizeof(AVFrame*) * FIFO_BUFFER_GROW_NUM);
      if (err < 0) return SetLastError(__LINE__, "av_fifo_grow", err);
    }
    AVFrame* tmp = frame.release();
    av_fifo_generic_write(list, &tmp, sizeof(tmp), nullptr);
#else
  auto enqueue_frame = [this](AVFifo* list, AutoFrame& frame) {
    assert(list != nullptr && frame != nullptr);
    assert(av_fifo_can_read(list) + av_fifo_can_write(list) < 1024);
    if (av_fifo_can_write(list) < 1) {
      int err = av_fifo_grow2(list, FIFO_BUFFER_GROW_NUM);
      if (err < 0) return SetLastError(__LINE__, "av_fifo_grow2", err);
    }
    AVFrame* tmp = frame.release();
    av_fifo_write(list, &tmp, 1);
#endif
  };

  last_audio_time = std::chrono::steady_clock::now();

  for (int i = 0; i < AV_STREAMS_NB; ++i) {
    assert(!queued_frames[i]);
#if LIBAVUTIL_VERSION_MAJOR < 57
    queued_frames[i].reset(av_fifo_alloc_array(32, sizeof(AVFrame*)));
#else
    queued_frames[i].reset(av_fifo_alloc2(MAX_QUEUED_PACKETS, sizeof(AVFrame*), 0));
#endif
    if (!queued_frames[i]) {
#if LIBAVUTIL_VERSION_MAJOR < 57
      return SetLastError(__LINE__, "av_fifo_alloc_array", AVERROR(ENOMEM));
#else
      return SetLastError(__LINE__, "av_fifo_alloc2", AVERROR(ENOMEM));
#endif
    }
  }

  on_start();

  AutoFrame sw_frame, in_frame(av_frame_alloc());
  if (!in_frame) return SetLastError(__LINE__, "av_frame_alloc", AVERROR(ENOMEM));

  while ((state_ & S_TERMINATE) == 0) {
    bool need_pause = (state_ & S_PLAYING) == 0;
    if (is_paused != need_pause) {
      is_paused = need_pause;
      if (is_paused) on_pause();
      else on_play();
    }

    if (play_reset_needed_) {
      for (int i = 0; i < AV_STREAMS_NB; ++i) {
        if (queued_frames[i]) clear_queued_frames(queued_frames[i]);
        if (decoder_[i]) avcodec_flush_buffers(decoder_[i].get());
      }
      play_reset_needed_ = false;
    }

    AutoPacket pkt(DecodePacketQueueGet());
    if (!pkt) continue;

    AVCodecContext *decoder = nullptr;
#if LIBAVUTIL_VERSION_MAJOR < 57
    AVFifoBuffer* frame_list = nullptr;
#else
    AVFifo* frame_list = nullptr;
#endif
    for (int i = 0; i < AV_STREAMS_NB; ++i) {
      if (streams_[i] != nullptr && streams_[i]->index == pkt->stream_index) {
        decoder = decoder_[i].get();
        frame_list = queued_frames[i].get();
        break;
      }
    }
    if (nullptr == decoder)
      continue;

    //按解码顺序发送packet
    err = avcodec_send_packet(decoder, pkt.get());
    if (err < 0) return SetLastError(__LINE__, "avcodec_send_packet", err);

    pkt.reset(); //不再使用，可以释放掉

    while ((state_ & S_TERMINATE) == 0) {
      //按显示顺序输出frame
      err = avcodec_receive_frame(decoder, in_frame.get());
      if (err == AVERROR(EAGAIN)) {
        break;
      } else if (err == AVERROR_EOF) {
        avcodec_flush_buffers(decoder);
        break;
      } else if (err < 0) {
        return SetLastError(__LINE__, "avcodec_receive_frame", err);
      }

      if (in_frame->pts == AV_NOPTS_VALUE) {
        av_frame_unref(in_frame.get());
        continue;
      }

      AVFrame* frame;
      if (in_frame->hw_frames_ctx != nullptr) {
        /* retrieve data from GPU to CPU */
        sw_frame.reset(av_frame_alloc());
        if (!sw_frame) return SetLastError(__LINE__, "av_frame_alloc", AVERROR(ENOMEM));
        err = av_hwframe_transfer_data(sw_frame.get(), in_frame.get(), 0);
        if (err < 0) return SetLastError(__LINE__, "av_hwframe_transfer_data", err);
        err = av_frame_copy_props(sw_frame.get(), in_frame.get());
        if (err < 0) return SetLastError(__LINE__, "av_frame_copy_props", err);
        //fprintf(stderr, "ooooooooooooooooooooooo2 %d %d %d %d\n",
        //    in_frame->format, sw_frame->format, sw_frame->width, sw_frame->height);
        av_frame_unref(in_frame.get());
        frame = sw_frame.get();
      } else {
        frame = in_frame.get();
      }

      AutoFrame clone_frame(av_frame_clone(frame));
      if (!clone_frame)
        return SetLastError(__LINE__, "av_frame_clone", AVERROR(ENOMEM));
      enqueue_frame(frame_list, clone_frame);

      av_frame_unref(frame);
    }

    for ( ;; ) {
      bool wait_and_play = true;
      int current_stream_id = -1;
      AVFrame *current_frame;

      for (int i = 0; i < AV_STREAMS_NB; ++i) {
        if (!decoder_[i]) continue;

        AVFrame* frame;
      //__again_peek_frame:
#if LIBAVUTIL_VERSION_MAJOR < 57
        if (av_fifo_size(queued_frames[i].get()) < (int)sizeof(frame)) {
#else
        if (av_fifo_can_read(queued_frames[i].get()) < 1) {
#endif
          if ((state_ & S_COMPLETED) == 0)
            wait_and_play = false;
          continue;
        }
#if LIBAVUTIL_VERSION_MAJOR < 57
        av_fifo_generic_peek(queued_frames[i].get(), &frame, sizeof(frame), nullptr);
#else
        av_fifo_peek(queued_frames[i].get(), &frame, 1, 0);
#endif
        assert(frame != nullptr);

        assert(streams_[i] != nullptr);

        /* best_effort_timestamp大多数情况下等于pts。
         * fdk-aac解码的时候如果设置了level_limit，pts会减去一个解码用时，在这里
         * 会导致音画不同步，如果要使用fdk-aac解码，注意把level_limit设置成不启用。
         */
        //if (frame->best_effort_timestamp < streams_[i]->start_time) {
        //  fprintf(stderr, "ooooooooooo %d %lld %lld %lld %lld\n",
        //      i, frame->pts, frame->pkt_pts, frame->best_effort_timestamp,
        //      streams_[i]->start_time);
        //  av_fifo_drain2(queued_frames[i].get(), 1);
        //  av_frame_free(&frame);
        //  goto __again_peek_frame;
        //}

        if (current_stream_id < 0 || av_compare_ts(
            frame->best_effort_timestamp, streams_[i]->time_base,
            current_frame->best_effort_timestamp,
            streams_[current_stream_id]->time_base) < 0) {
          current_stream_id = i;
          current_frame = frame;
        }
      }

      if (current_stream_id < 0)
        break;

      if (!live_streaming_) { /* play as real frame rate */

        int64_t current_pts = av_rescale_q(
            current_frame->best_effort_timestamp,
            streams_[current_stream_id]->time_base,
            AV_TIME_BASE_Q);
        //fprintf(stderr, "zzzzzzzzzzzzzzzzzzzz %lld %lld\n",
        //    current_pts, sync_start_time);
        auto now = std::chrono::steady_clock::now();

        if (time_sync_needed_) {
          if (last_audio_time > now) {
            if (!wait_and_play) break;
            std::this_thread::sleep_until(last_audio_time);
            now = last_audio_time;
          } else {
            play_start_time = now;
            sync_start_time = current_pts;
          }
          time_sync_needed_ = false;
        }

        auto play_time = play_start_time +
            std::chrono::microseconds(current_pts - sync_start_time);
        if (play_time > now) {
          if (!wait_and_play) break;
          std::this_thread::sleep_until(play_time);
          now = play_time;
        }

        if (current_stream_id == AV_AUDIO) {
          //int64_t next_pts = av_rescale_delta(
          //    streams_[current_stream_id]->time_base, // input time base
          //    current_frame->best_effort_timestamp,   // input pts
          //    AVRational{1, current_frame->sample_rate}, // duration time base
          //    current_frame->nb_samples,   // duration
          //    &next_pts[index],
          //    AV_TIME_BASE_Q);            // output time base
          int64_t next_pts = current_pts +
              av_rescale_q_rnd(current_frame->nb_samples,
                  AVRational{1, current_frame->sample_rate},
                  AV_TIME_BASE_Q, AV_ROUND_UP);
          last_audio_time = play_start_time +
              std::chrono::microseconds(next_pts - sync_start_time);
        }
      } /* not live streaming */

      if (current_stream_id == AV_VIDEO) {
        //fprintf(stderr, "vvvvvvvvvvvvvvvvvvvvvvvvv %lld %lld %lld\n",
        //    sync_start_time,
        //    current_pts,
        //    std::chrono::duration_cast<std::chrono::microseconds>(delta).count());
        on_video(current_frame);
      } else if (current_stream_id == AV_AUDIO) {
        //fprintf(stderr, "aaaaaaaaaaaaaaaaaaaaaaaaa %lld %lld %lld\n",
        //    sync_start_time,
        //    current_pts,
        //    std::chrono::duration_cast<std::chrono::microseconds>(delta).count());
        on_audio(current_frame);
      }

#if LIBAVUTIL_VERSION_MAJOR < 57
      av_fifo_drain(queued_frames[current_stream_id].get(), sizeof(current_frame));
#else
      av_fifo_drain2(queued_frames[current_stream_id].get(), 1);
#endif
      av_frame_free(&current_frame);
    }
  }
}

} //namespace net
} //namespace bee
