#include "BeeFFmpegUtils.h"
#include "beenet/logger.h"

namespace BeeFFmpegUtils {

static void SetLastError(int lineno, const char* prefix, int av_err)
{
  char errstr[AV_ERROR_MAX_STRING_SIZE];
  av_strerror(av_err, errstr, sizeof(errstr));
  bee::logger::log(bee::logger::BEE_ERROR, __FILE__, lineno, "%s %s", prefix, errstr);
}

static void SetLastError(int lineno, const char* prefix, const char* fmt, ...)
{
  char errstr[1024];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(errstr, sizeof(errstr), fmt, ap);
  va_end(ap);
  if (n >= (int)sizeof(errstr)) errstr[sizeof(errstr)-1] = '\0';
  bee::logger::log(bee::logger::BEE_ERROR, __FILE__, lineno, "%s %s", prefix, errstr);
}

void Resample::Reset(AVSampleFormat sample_fmt,
#if LIBAVUTIL_VERSION_MAJOR < 57
  int channels,
#else
  const AVChannelLayout& channel_layout,
#endif
  int sample_rate, size_t frame_size)
{
  if (sample_fmt != out_sample_fmt_ || sample_rate != out_sample_rate_ ||
#if LIBAVUTIL_VERSION_MAJOR < 57
      channels != out_channels_) {
#else
      av_channel_layout_compare(&channel_layout, &out_channel_layout_) != 0) {
#endif
    swr_ctx_.reset();
    swr_buffers_.reset();
    swr_buffer_samples_ = 0;
    audio_fifo_.reset();
  }

  out_sample_fmt_ = sample_fmt;
#if LIBAVUTIL_VERSION_MAJOR < 57
  out_channels_ = channels;
#else
  av_channel_layout_copy(&out_channel_layout_, &channel_layout);
#endif
  out_sample_rate_ = sample_rate;
  out_frame_size_ = frame_size;
}

void Resample::InputData(const uint8_t* const* data,
  AVSampleFormat sample_fmt, int sample_rate,
#if LIBAVUTIL_VERSION_MAJOR < 57
  int channels,
#else
  const AVChannelLayout& channel_layout,
#endif
  size_t nb_samples)
{
  //assert(AV_SAMPLE_FMT_NONE != out_sample_fmt_);

  int err;

  //assert(!av_sample_fmt_is_planar(sample_fmt));
  const uint8_t** audio_bufs = const_cast<const uint8_t**>(data);

  if (sample_fmt == out_sample_fmt_ &&
#if LIBAVUTIL_VERSION_MAJOR < 57
      channels == out_channels_ &&
#else
      av_channel_layout_compare(&channel_layout, &out_channel_layout_) == 0 &&
#endif
      sample_rate == out_sample_rate_) {

    if (swr_ctx_) {
      swr_ctx_.reset();
      swr_buffers_.reset();
      swr_buffer_samples_ = 0;
    }

  } else {

    do {
      if (swr_ctx_ &&
          sample_fmt == last_in_sample_fmt_ &&
#if LIBAVUTIL_VERSION_MAJOR < 57
          channels == last_in_channels_ &&
#else
          av_channel_layout_compare(&channel_layout, &last_in_channel_layout_) == 0 &&
#endif
          sample_rate == last_in_sample_rate_)
        break;

      swr_ctx_.reset();
      swr_buffers_.reset();
      swr_buffer_samples_ = 0;

      SwrContext* swr_ctx = nullptr;
#if LIBAVUTIL_VERSION_MAJOR < 57
      swr_ctx = swr_alloc_set_opts(nullptr,
          av_get_default_channel_layout(out_channels_),
          out_sample_fmt_,
          out_sample_rate_,
          av_get_default_channel_layout(channels),
          sample_fmt,
          sample_rate,
          0, nullptr);
      if (swr_ctx == nullptr) {
        return SetLastError(__LINE__, "swr_alloc_set_opts", AVERROR(ENOMEM));
      }
#else
      if ((err = swr_alloc_set_opts2(&swr_ctx,
          &out_channel_layout_, out_sample_fmt_, out_sample_rate_,
          const_cast<AVChannelLayout*>(&channel_layout),
          sample_fmt, sample_rate, 0, nullptr)) < 0) {
        return SetLastError(__LINE__, "swr_alloc_set_opts2", AVERROR(ENOMEM));
      }
#endif

      /* initialize the resampling context */
      if ((err = swr_init(swr_ctx)) < 0) {
        swr_free(&swr_ctx);
        return SetLastError(__LINE__, "swr_init", err);
      }

      swr_ctx_.reset(swr_ctx);

      last_in_sample_fmt_ = sample_fmt;
      last_in_sample_rate_ = sample_rate;
#if LIBAVUTIL_VERSION_MAJOR < 57
      last_in_channels_ = channels;
#else
      av_channel_layout_copy(&last_in_channel_layout_, &channel_layout);
#endif

    } while (0);

    int swr_nb_samples = av_rescale_rnd(
        swr_get_delay(swr_ctx_.get(), sample_rate) + nb_samples,
        out_sample_rate_, sample_rate, AV_ROUND_UP);

    if (!swr_buffers_ || swr_buffer_samples_ < swr_nb_samples) {
      uint8_t** tmp = nullptr;
      err = av_samples_alloc_array_and_samples(
          &tmp, nullptr,
#if LIBAVUTIL_VERSION_MAJOR < 57
          out_channels_,
#else
          out_channel_layout_.nb_channels,
#endif
          swr_nb_samples, out_sample_fmt_, 0);
      if (err < 0) {
        return SetLastError(__LINE__, "av_samples_alloc_array_and_samples", err);
      }
      swr_buffers_.reset(tmp);
      swr_buffer_samples_ = swr_nb_samples;
    }

    err = swr_convert(swr_ctx_.get(), swr_buffers_.get(), swr_nb_samples,
                      audio_bufs, nb_samples);
    if (err < 0) {
      return SetLastError(__LINE__, "swr_convert", err);
    }

    audio_bufs = (const uint8_t**)swr_buffers_.get();
    nb_samples = err; //err here is converter samples number

  }

  if (!audio_fifo_) {
    audio_fifo_.reset(av_audio_fifo_alloc(out_sample_fmt_,
#if LIBAVUTIL_VERSION_MAJOR < 57
        out_channels_,
#else
        out_channel_layout_.nb_channels,
#endif
        std::max(out_frame_size_, nb_samples) + out_frame_size_));
    if (!audio_fifo_) {
      return SetLastError(__LINE__, "av_audio_fifo_alloc", AVERROR(ENOMEM));
    }
#if 0 /* av_audio_fifo_write会自动根据需要的空间扩展 */
  } else {
    int residue = av_audio_fifo_size(audio_fifo_.get());
    //if (residue > out_frame_size_) {
    //  av_audio_fifo_drain(audio_fifo_.get(), out_frame_size_);
    //  residue -= out_frame_size_;
    //}
    err = av_audio_fifo_realloc(audio_fifo_.get(), residue + nb_samples);
    if (err < 0) {
      return SetLastError(__LINE__, "av_audio_fifo_realloc", err);
    }
#endif
  }

  err = av_audio_fifo_write(audio_fifo_.get(), (void**)audio_bufs, nb_samples);
  if (err < 0) {
    return SetLastError(__LINE__, "av_audio_fifo_write", err);
  } else if (err != nb_samples) {
    return SetLastError(__LINE__, "av_audio_fifo_write", "audio frame write imcomplete");
  }

  while (av_audio_fifo_size(audio_fifo_.get()) >= out_frame_size_) {
    AutoFrame resample_frame(av_frame_alloc());
    if (!resample_frame) {
      return SetLastError(__LINE__, "av_frame_alloc", AVERROR(ENOMEM));
    }

    resample_frame->format = out_sample_fmt_;
#if LIBAVUTIL_VERSION_MAJOR < 57
    resample_frame->channel_layout = av_get_default_channel_layout(out_channels_),
    resample_frame->channels = out_channels_;
#else
    av_channel_layout_copy(&resample_frame->ch_layout, &out_channel_layout_);
#endif
    resample_frame->sample_rate = out_sample_rate_;
    resample_frame->nb_samples = out_frame_size_;

    err = av_frame_get_buffer(resample_frame.get(), 0);
    if (err < 0) return SetLastError(__LINE__, "av_frame_get_buffer", err);

    err = av_audio_fifo_read(audio_fifo_.get(),
        (void**)resample_frame->extended_data, resample_frame->nb_samples);
    if (err < 0) {
      return SetLastError(__LINE__, "av_audio_fifo_read", err);
    } else if (err != resample_frame->nb_samples) {
      return SetLastError(__LINE__, "av_audio_fifo_read", "audio frame read imcomplete");
    }

    audio_queue_.emplace_back(std::move(resample_frame));
  }
}

void Resample::InputFrame(const AVFrame* frame)
{
#if LIBAVUTIL_VERSION_MAJOR < 57
  return InputData(frame->data, (AVSampleFormat)frame->format,
      frame->sample_rate, frame->channels, frame->nb_samples);
#else
  return InputData(frame->data, (AVSampleFormat)frame->format,
      frame->sample_rate, frame->ch_layout, frame->nb_samples);
#endif
}

AutoFrame Resample::GetFrame()
{
  if (!audio_queue_.empty()) {
    AutoFrame frame = std::move(audio_queue_.front());
    audio_queue_.pop_front();
    return frame;
  }
  return nullptr;
}

#if 0
Spectrogram::Spectrogram() : resample_(
    resample_fmt_, resample_channel_layout_,
    resample_rate_, fft_win_size_)
{
  for (int ch = 0; ch < resample_channel_layout_.nb_channels; ++ch) {
    void* p = av_calloc(fft_win_size_, sizeof(FFTComplex));
    if (p == nullptr) {
      SetLastError(__LINE__, "av_calloc", AVERROR(ENOMEM));
      return;
    }
    fft_data_[ch].reset((FFTComplex*)p);
  }

  if (fft_.reset(av_fft_init(fft_bits_, 0)); !fft_) {
    SetLastError(__LINE__, "av_fft_init", AVERROR(ENOMEM));
    return;
  }
}

void Spectrogram::InputData(const uint8_t* const* data,
  AVSampleFormat sample_fmt, int sample_rate,
  const AVChannelLayout& channel_layout, size_t nb_samples)
{
  if (fft_) resample_.InputData(data, sample_fmt, sample_rate, channel_layout, nb_samples);
}

#define ARGB(a,r,g,b) (((uint32_t)(a) << 24) | ((r) << 16) | ((g) << 8) | (b))

static inline void PlotAudioFreq(AVFrame* out, int freq, int freq_max, double a)
{
  const int y0 = (1 - a) * out->height / 2 + 0.5;
  const int y1 = (1 + a) * out->height / 2 - 0.5;

  const int x0 = out->width * freq / freq_max;
  const int x1 = out->width * (freq + 1) / freq_max;

  for (int x = x0; x < x1 && x < out->width; ++x) {
    for (int y = y0; y < y1; ++y) {
      void* p = out->data[0] + y * out->linesize[0] + x * 4;
      *reinterpret_cast<uint32_t*>(p) = ARGB(255, 255, 255, 255);
    }
  }
}

bool Spectrogram::GetPicture(AVFrame* picture)
{
  AutoFrame in = resample_.GetFrame();
  if (!in) return false;

  assert(fft_);

#if 0
  for (int n = 0; n < picture->height; ++n)
    memset(picture->data[0] + picture->linesize[0] * n, 0, picture->width * 4);
#else
  for (int y = 0; y < picture->height; ++y) {
    void* p = picture->data[0] + picture->linesize[0] * y;
    for (int x = 0; x < picture->width; ++x)
      reinterpret_cast<uint32_t*>(p)[x] = ARGB(63, 0, 0, 0);
  }
#endif

  /* fill FFT input with the number of samples available */
  for (int ch = 0, n; ch < resample_channel_layout_.nb_channels; ++ch) {
    const float* p = (float*)in->extended_data[ch];
    FFTComplex* fft_data = fft_data_[ch].get();

    for (n = 0; n < in->nb_samples; ++n) {
      fft_data[n].re = p[n];
      fft_data[n].im = 0;
    }
    for (; n < fft_win_size_; ++n) {
      fft_data[n].re = 0;
      fft_data[n].im = 0;
    }

    av_fft_permute(fft_.get(), fft_data);
    av_fft_calc(fft_.get(), fft_data);
  }

  double max_amplitude = 16/*32*/;
  double amplitudes[fft_freq_];

  memset(amplitudes, 0, sizeof(amplitudes));

  /* run FFT on each samples set */
  for (int ch = 0; ch < resample_channel_layout_.nb_channels; ch++) {
    FFTComplex* fft_data = fft_data_[ch].get();
    #define RE(x) fft_data[x].re
    #define IM(x) fft_data[x].im
    #define M(a, b) sqrt((a) * (a) + (b) * (b))
    #define P(a, b) atan2((b), (a))
    //#define PI 3.14159265358979323846  /* pi */

    amplitudes[0] += M(RE(0), 0);
    if (max_amplitude < amplitudes[0]) max_amplitude = amplitudes[0];
    for (int f = 1; f < fft_freq_; ++f) {
      amplitudes[f] += M(RE(f), IM(f));
      if (max_amplitude < amplitudes[f]) max_amplitude = amplitudes[f];
    }
  }

  for (int f = 0; f < fft_freq_; ++f) {
    double a = amplitudes[f] / max_amplitude;
    PlotAudioFreq(picture, f, fft_freq_, a);
  }

  return true;
}
#endif

#if 0
AudioFilter::AudioFilter() : graph_(avfilter_graph_alloc())
{
  if (!graph_) SetLastError(__LINE__, "avfilter_graph_alloc", AVERROR(ENOMEM));
}

struct KV_FILTER_CONFIG {
  const char *key;
  struct { const char *s; int64_t i; } val;
};

static AVFilterContext * AddFilter(AVFilterGraph* graph,
  const char* filter_name, const char* inst_name, const KV_FILTER_CONFIG* config)
{
  const AVFilter *filter = avfilter_get_by_name(filter_name);
  if (nullptr == filter) {
    SetLastError(__LINE__, "avfilter_get_by_name", "filter (%s) not found", filter_name);
    return nullptr;
  }

  AVFilterContext* ctx = avfilter_graph_alloc_filter(graph, filter, inst_name);
  if (ctx == nullptr) {
    SetLastError(__LINE__, "avfilter_graph_alloc_filter", AVERROR(ENOMEM));
    return nullptr;
  }

  if (config != nullptr) {
    AVDictionary* options = nullptr;

    for (size_t i = 0; nullptr != config[i].key; ++i) {
      if (config[i].val.s != nullptr) {
        av_dict_set(&options, config[i].key, config[i].val.s, 0);
      } else {
        av_dict_set_int(&options, config[i].key, config[i].val.i, 0);
      }
    }

    int err = avfilter_init_dict(ctx, &options);
    if (err < 0) {
      SetLastError(__LINE__, "avfilter_init_dict", err);
      av_dict_free(&options);
      return nullptr;
    }

    av_dict_free(&options);
  }

  return ctx;
}

bool AudioFilter::AddInput(
  AVSampleFormat sample_fmt, const char* channel_layout_str, int sample_rate)
{
  assert(abuffer_src_ == nullptr && last_filter_ == nullptr);

  if (!graph_ || abuffer_src_ != nullptr)
    return false;

  const KV_FILTER_CONFIG args[] = {
    { "sample_fmt"     , { av_get_sample_fmt_name(sample_fmt) } },
    { "sample_rate"    , { .s = nullptr, .i = sample_rate }     },
    { "channel_layout" , { .s = channel_layout_str }            },
    { nullptr                                                   }
  };

  abuffer_src_ = AddFilter(graph_.get(), "abuffer", "src", args);
  if (abuffer_src_ == nullptr)
    return false;

  last_filter_ = abuffer_src_;

  return true;
}

bool AudioFilter::AddOutput()
{
  assert(!abuffer_out_ && last_filter_ != nullptr);

  if (abuffer_out_ || last_filter_ == nullptr)
    return false;

  abuffer_out_ = AddFilter(graph_.get(), "abuffersink", "out", nullptr);
  if (abuffer_out_ == nullptr) return false;

  int err = avfilter_link(last_filter_, 0, abuffer_out_, 0);
  if (err < 0) {
    SetLastError(__LINE__, "avfilter_link", err);
    return false;
  }

  err = avfilter_graph_config(graph_.get(), nullptr);
  if (err < 0) {
    SetLastError(__LINE__, "avfilter_graph_config", err);
    return false;
  }

  last_filter_ = nullptr;
  return true;
}

bool AudioFilter::AddFilterVolume(float gain)
{
  assert(last_filter_ != nullptr);

  if (last_filter_ == nullptr)
    return false;

  char gain_str[64];
  snprintf(gain_str, sizeof(gain_str), "%.f", gain);

  const KV_FILTER_CONFIG args[] = {
    { "volume"   , { gain_str } },
    { "precision", { "float"  } },
    { "eval"     , { "frame"  } },
    { nullptr                   },
  };

  auto* new_filter = AddFilter(graph_.get(), "volume", "volume", args);
  if (new_filter == nullptr) return false;

  int err = avfilter_link(last_filter_, 0, new_filter, 0);
  if (err < 0) {
    SetLastError(__LINE__, "avfilter_link", err);
    return false;
  }

  last_filter_ = new_filter;

  return true;
}

bool AudioFilter::AddFilterFormat(
  AVSampleFormat sample_fmt, const char* channel_layout_str, int sample_rate)
{
  assert(last_filter_ != nullptr);

  if (last_filter_ == nullptr)
    return false;

  const KV_FILTER_CONFIG args[] = {
    { "sample_fmts"    , { av_get_sample_fmt_name(sample_fmt) } },
    { "sample_rates"   , { .s = nullptr, .i = sample_rate }     },
    { "channel_layouts", { .s = channel_layout_str }            },
    { nullptr                                                   },
  };

  auto* new_filter = AddFilter(graph_.get(), "aformat", "aformat", args);
  if (new_filter == nullptr) return false;

  int err = avfilter_link(last_filter_, 0, new_filter, 0);
  if (err < 0) {
    SetLastError(__LINE__, "avfilter_link", err);
    return false;
  }

  last_filter_ = new_filter;

  return true;
}

bool AudioFilter::InputFrame(const AVFrame* frame)
{
  assert(abuffer_src_ != nullptr && abuffer_out_ != nullptr);

  if (abuffer_src_ == nullptr || abuffer_out_ == nullptr)
    return false;

  int err = av_buffersrc_add_frame(abuffer_src_, const_cast<AVFrame*>(frame));
  if (err < 0) {
    SetLastError(__LINE__, "av_buffersrc_add_frame", err);
    return false;
  }

  return true;
}

AutoFrame AudioFilter::GetFrame()
{
  assert(graph_ && abuffer_src_ != nullptr && abuffer_out_ != nullptr);

  if (abuffer_src_ == nullptr || abuffer_out_ == nullptr)
    return nullptr;

  AutoFrame frame(av_frame_alloc());
  if (!frame) {
    SetLastError(__LINE__, "av_frame_alloc", AVERROR(ENOMEM));
    return nullptr;
  }

  int err = av_buffersink_get_frame(abuffer_out_, frame.get());
  if (err == AVERROR(EAGAIN)) {
    return nullptr;
  } else if (err < 0) {
    SetLastError(__LINE__, "av_buffersink_get_frame", err);
    return nullptr;
  }

  return frame;
}

bool AudioFilter::SetOption(AVFilterContext* ctx, const char* key, const char* val)
{
  AVDictionary *options = nullptr;
  av_dict_set(&options, key, val, 0);
  int err = avfilter_init_dict(ctx, &options);
  if (err < 0) SetLastError(__LINE__, "avfilter_init_dict", err);
  av_dict_free(&options);
  return (err == 0);
}
#endif

} // namespace BeeFFmpegUtils
