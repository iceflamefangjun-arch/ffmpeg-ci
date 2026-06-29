#ifndef BEE_FFMPEG_UTILS_H_INCLUDED
#define BEE_FFMPEG_UTILS_H_INCLUDED

extern "C"  {
#include "libavformat/avformat.h"
#include "libavutil/channel_layout.h"
#include "libavutil/audio_fifo.h"
#include "libavutil/samplefmt.h"
#include "libavutil/imgutils.h"
#include "libswresample/swresample.h"
#include "libavcodec/avfft.h"
//#include "libavfilter/avfilter.h"
//#include "libavfilter/buffersrc.h"
//#include "libavfilter/buffersink.h"
}

#include <memory>
#include <deque>
#include <cassert>

namespace BeeFFmpegUtils {

struct FFmpegDeleter {
  void operator()(AVFrame* p) { av_frame_free(&p); }
  void operator()(uint8_t** p) {
    if (nullptr != p) { av_freep(&p[0]); av_free(p); }
  }
  void operator()(SwrContext* p) { swr_free(&p); }
  void operator()(AVAudioFifo* p) { av_audio_fifo_free(p); }
  void operator()(FFTContext* p) { av_fft_end(p); }
  void operator()(FFTComplex* p) { av_freep(&p); }
  //void operator()(AVFilterGraph* p) { avfilter_graph_free(&p); }
  //void operator()(AVFilterContext* p) { avfilter_free(p); }
};

using AutoFrame = std::unique_ptr<AVFrame, FFmpegDeleter>;
using AutoSwrContext = std::unique_ptr<SwrContext, FFmpegDeleter>;
using AutoAudioFifo = std::unique_ptr<AVAudioFifo, FFmpegDeleter>;
using AutoSampleBufs = std::unique_ptr<uint8_t*, FFmpegDeleter>;
using AutoFFTContext = std::unique_ptr<FFTContext, FFmpegDeleter>;
using AutoFFTComplexArray = std::unique_ptr<FFTComplex, FFmpegDeleter>;
//using AutoFilterGraph = std::unique_ptr<AVFilterGraph, FFmpegDeleter>;
//using AutoFilterContext = std::unique_ptr<AVFilterContext, FFmpegDeleter>;

class Resample {
public:
  Resample() = default;
  ~Resample() = default;

  void Reset(AVSampleFormat sample_fmt,
#if LIBAVUTIL_VERSION_MAJOR < 57
             int channels,
#else
             const AVChannelLayout& channel_layout,
#endif
             int sample_rate,
             size_t frame_size);

  void InputData(const uint8_t* const* data,
                 AVSampleFormat sample_fmt,
                 int sample_rate,
#if LIBAVUTIL_VERSION_MAJOR < 57
                 int channels,
#else
                 const AVChannelLayout& channel_layout,
#endif
                 size_t nb_samples);

  void InputFrame(const AVFrame* frame);

  AutoFrame GetFrame();

private:
  AVSampleFormat out_sample_fmt_ = AV_SAMPLE_FMT_NONE;
#if LIBAVUTIL_VERSION_MAJOR < 57
  int out_channels_ = 0;
#else
  AVChannelLayout out_channel_layout_ = { (AVChannelOrder)-1, 0 };
#endif
  int out_sample_rate_ = 0;
  size_t out_frame_size_ = 0;

  AVSampleFormat last_in_sample_fmt_;
  int last_in_sample_rate_;
#if LIBAVUTIL_VERSION_MAJOR < 57
  int last_in_channels_;
#else
  AVChannelLayout last_in_channel_layout_;
#endif

  AutoSwrContext swr_ctx_;
  AutoSampleBufs swr_buffers_;
  size_t swr_buffer_samples_ = 0; // 当前swr_buffers_的空间大小
                                  // 用于判断是否空间足够或者需要重新分配更大空间

  AutoAudioFifo audio_fifo_;

  std::deque<AutoFrame> audio_queue_;
};

#if 0
class Spectrogram {
public:
  Spectrogram();
  ~Spectrogram() = default;

  void InputData(const uint8_t* const* data, AVSampleFormat sample_fmt,
                 int sample_rate, const AVChannelLayout& channels,
                 size_t nb_samples);

  bool GetPicture(AVFrame* frame);

private:
  Resample resample_;

  static constexpr AVSampleFormat resample_fmt_ = AV_SAMPLE_FMT_FLTP;
  static constexpr AVChannelLayout resample_channel_layout_ = AV_CHANNEL_LAYOUT_MONO;
  static constexpr int resample_rate_ = 8192;
  static constexpr int fft_size_ = 512;
  static constexpr int fft_bits_ = 9; //av_log2(fft_size_);
  static constexpr int fft_freq_ = 256; //1 << (fft_bits - 1);
  static constexpr int fft_win_size_ = 512; //fft_freq_ << 1;

  AutoFFTContext fft_;
  AutoFFTComplexArray fft_data_[resample_channel_layout_.nb_channels];
};
#endif

#if 0
class AudioFilter {
public:
  AudioFilter();
  ~AudioFilter() = default;

  bool AddInput(AVSampleFormat sample_fmt,
                const char* channel_layout_str,
                int sample_rate);
  bool AddOutput();

  bool AddFilterFormat(AVSampleFormat sample_fmt,
                       const char* channel_layout_str,
                       int sample_rate);
  bool AddFilterVolume(float gain=1.0f);

  AVFilterContext * GetLastFilter() { return last_filter_; }

  bool SetOption(AVFilterContext* ctx, const char* key, const char* val);

  bool InputFrame(const AVFrame* frame);
  AutoFrame GetFrame();

private:
  AutoFilterGraph graph_;
  AVFilterContext* abuffer_src_ = nullptr;
  AVFilterContext* abuffer_out_ = nullptr;
  AVFilterContext* last_filter_ = nullptr;
};
#endif

} // namespace BeeFFmpegUtils

#endif
