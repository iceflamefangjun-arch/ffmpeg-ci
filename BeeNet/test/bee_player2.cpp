#include "BeeAVPlayer.h"
#include "BeeFFmpegUtils.h"
#include "beenet/interface.h"
#include "beenet/logger.h"
#include <windows.h>
#include <dsound.h>
#include <deque>
#include <assert.h>

static const char kClassName[] = "BeeNet_FFmpeg_Player";
static DWORD kUIThreadId = 0;

#define UI_THREAD_CALLBACK WM_APP + 1
#define UI_CREATE_WINDOW   1
#define UI_DESTROY_WINDOW  2

#define AUDIO_BUFFERS_NB 3
#define BUFFERNOTIFYSIZE 192000

class BeeWindowsPlayer : public bee::net::BeeAVPlayer {
public:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  bool CreateUI();
  void DestroyUI();

private:
  void OnPaint();
  bool InitSound(int channels, int sample_rate, int bytes_per_sample);

  void on_start() override;
  void on_video(AVFrame* frame) override;
  void on_audio(AVFrame* frame) override;
  void on_play() override;
  void on_pause() override;
  void on_stop() override;
  void on_error(const char*, int, const char*, const char*) override;

  struct InnerDeleter {
    void operator()(SwsContext* p) { sws_freeContext(p); }
  };

  HWND window_ = NULL;
  BITMAPINFO bmi_;
  int width_ = 1024, height_ = 768;
  bool need_resize_ = false;
  std::unique_ptr<uint8_t[]> draw_buffer_;
  size_t draw_buffer_size_ = 0;
  std::mutex draw_buffer_mtx_;
  SwsContext* sws_ctx_ = nullptr;

  LPDIRECTSOUND8 ds_ctx_ = NULL;
  LPDIRECTSOUNDBUFFER ds_buffer_ = NULL;
  DWORD audio_write_cursor_ = -1;
  BeeFFmpegUtils::Resample resample_;
};

LRESULT CALLBACK BeeWindowsPlayer::WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
  BeeWindowsPlayer* player =
      reinterpret_cast<BeeWindowsPlayer*>(::GetWindowLongPtr(hwnd, GWLP_USERDATA));

  if (player == nullptr) {
    if (WM_CREATE != msg)
      return ::DefWindowProc(hwnd, msg, wp, lp);

    CREATESTRUCT* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    player = reinterpret_cast<BeeWindowsPlayer*>(cs->lpCreateParams);
    player->window_ = hwnd;
    ::SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(player));
  }

  switch (msg) {
    case WM_ERASEBKGND:
      return 0;
    case WM_PAINT:
      player->OnPaint();
      return 0;
    case WM_SETFOCUS:
      return 0;
    case WM_SIZE:
      break;
    case WM_CTLCOLORSTATIC:
      return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
    case WM_COMMAND:
      return 0;
    case WM_CLOSE:
      player->DestroyUI();
      break;
  }

  return ::DefWindowProc(hwnd, msg, wp, lp);
}

bool BeeWindowsPlayer::CreateUI()
{
  assert(window_ == NULL);

  ZeroMemory(&bmi_, sizeof(bmi_));
  bmi_.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi_.bmiHeader.biPlanes = 1;
  bmi_.bmiHeader.biBitCount = 32;
  bmi_.bmiHeader.biCompression = BI_RGB;
  //bmi_.bmiHeader.biWidth = width_;
  //bmi_.bmiHeader.biHeight = -height_;
  //bmi_.bmiHeader.biSizeImage = width_ * height_ * (bmi_.bmiHeader.biBitCount >> 3);

  window_ = CreateWindowEx(WS_EX_OVERLAPPEDWINDOW, kClassName, URL(),
                           WS_OVERLAPPEDWINDOW | WS_VISIBLE | WS_CLIPCHILDREN,
                           CW_USEDEFAULT, CW_USEDEFAULT, width_, height_,
                           NULL, NULL, GetModuleHandle(NULL), this);
  if (window_ == NULL) {
    BEE_LOG_ERROR("CreateWindowEx error code: %d", GetLastError());
    return false;
  }

  //HFONT font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT))
  //SendMessage(window_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);

  //ShowWindow(window_, SW_NORMAL);
  UpdateWindow(window_);

  return true;
}

void BeeWindowsPlayer::OnPaint()
{
  assert(window_ != NULL);

  std::lock_guard<std::mutex> lck(draw_buffer_mtx_);

  if (width_ == 0 || height_ == 0)
    return;

  if (need_resize_) {
    bmi_.bmiHeader.biWidth = width_;
    bmi_.bmiHeader.biHeight = -height_;
    bmi_.bmiHeader.biSizeImage = width_ * height_ * (bmi_.bmiHeader.biBitCount >> 3);
  }

  PAINTSTRUCT ps;
  BeginPaint(window_, &ps);

  RECT rc;
  GetClientRect(window_, &rc);

  HDC dc_mem = CreateCompatibleDC(ps.hdc);
  SetStretchBltMode(dc_mem, HALFTONE);

  // Set the map mode so that the ratio will be maintained for us.
  HDC all_dc[] = {ps.hdc, dc_mem};
  for (size_t i = 0; i < sizeof(all_dc) / sizeof(HDC); ++i) {
    SetMapMode(all_dc[i], MM_ISOTROPIC);
    SetWindowExtEx(all_dc[i], width_, height_, NULL);
    SetViewportExtEx(all_dc[i], rc.right, rc.bottom, NULL);
  }

  HBITMAP bmp_mem = CreateCompatibleBitmap(ps.hdc, rc.right, rc.bottom);
  HGDIOBJ bmp_old = SelectObject(dc_mem, bmp_mem);

  POINT logical_area = {rc.right, rc.bottom};
  DPtoLP(ps.hdc, &logical_area, 1);

  HBRUSH brush = CreateSolidBrush(RGB(0, 0, 0));
  RECT logical_rect = {0, 0, logical_area.x, logical_area.y};
  FillRect(dc_mem, &logical_rect, brush);
  DeleteObject(brush);

  int x = (logical_area.x / 2) - (width_ / 2);
  int y = (logical_area.y / 2) - (height_ / 2);

  StretchDIBits(dc_mem, x, y, width_, height_, 0, 0, width_, height_,
                draw_buffer_.get(), &bmi_, DIB_RGB_COLORS, SRCCOPY);

  BitBlt(ps.hdc, 0, 0, logical_area.x, logical_area.y, dc_mem, 0, 0, SRCCOPY);

  // Cleanup.
  SelectObject(dc_mem, bmp_old);
  DeleteObject(bmp_mem);
  DeleteDC(dc_mem);

  EndPaint(window_, &ps);
}

void BeeWindowsPlayer::DestroyUI()
{
  if (window_ != NULL) {
    DestroyWindow(window_);
    window_ = NULL;
  }
  bee::net::BeeAVPlayer::close();
}

bool BeeWindowsPlayer::InitSound(int channels, int sample_rate, int bytes_per_sample)
{
  if (ds_ctx_ == NULL) {
    if (DS_OK != DirectSoundCreate8(&DSDEVID_DefaultPlayback, &ds_ctx_, NULL)) {
      BEE_LOG_ERROR("DirectSoundCreate8 error code: %d", GetLastError());
      return false;
    }

    HWND hWnd = NULL;
    if (NULL != (hWnd = GetForegroundWindow()) ||
        NULL != (hWnd = GetDesktopWindow())    ||
        NULL != (hWnd = GetConsoleWindow())) {
      if (DS_OK != ds_ctx_->SetCooperativeLevel(hWnd, DSSCL_NORMAL)) {
        BEE_LOG_ERROR("SetCooperativeLevel error code: %d", GetLastError());
        return false;
      }
    }
  }

  if (ds_buffer_ == NULL) {
    WAVEFORMATEX format;
    ZeroMemory(&format, sizeof(format));
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = channels;
    format.nSamplesPerSec = sample_rate;
    format.nAvgBytesPerSec = channels * sample_rate * bytes_per_sample;
    format.nBlockAlign = bytes_per_sample * channels;
    format.wBitsPerSample = bytes_per_sample * 8;

    DSBUFFERDESC desc;
    ZeroMemory(&desc, sizeof(desc));
    desc.dwSize = sizeof(desc);
    desc.dwFlags = DSBCAPS_GLOBALFOCUS | DSBCAPS_GETCURRENTPOSITION2;
                /* DSBCAPS_CTRLFX | DSBCAPS_CTRLPOSITIONNOTIFY |*/
    desc.dwBufferBytes = AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE;
    desc.lpwfxFormat = &format;

    if (DS_OK != ds_ctx_->CreateSoundBuffer(&desc, &ds_buffer_, nullptr)) {
      BEE_LOG_ERROR("CreateSoundBuffer error code: %d", GetLastError());
      return false;
    }

    //ds_buffer_->SetCurrentPosition(0);
    ds_buffer_->Play(0, 0, DSBPLAY_LOOPING);
    //ds_next_offset_ = BUFFERNOTIFYSIZE;
  }

  return true;
}

void BeeWindowsPlayer::on_start()
{
  do {
    auto* params = GetAudioCodecParams();
    if (params == nullptr) break;

    int sample_rate = params->sample_rate;//48000;

#if LIBAVUTIL_VERSION_MAJOR < 57
    int channels = params->channels;
    if (!(channels > 0)) break;
    if (channels > 2) channels = 2;

    resample_.Reset(AV_SAMPLE_FMT_S16, channels, sample_rate,
        params->frame_size > 0 ? params->frame_size : 1024);
#else
    AVChannelLayout channel_layout;
    if (!av_channel_layout_check(&params->ch_layout)) break;
    if (params->ch_layout.nb_channels > 2) {
      av_channel_layout_default(&channel_layout, 2);
    } else {
      av_channel_layout_copy(&channel_layout, &params->ch_layout);
    }
    int channels = channel_layout.nb_channels;

    resample_.Reset(AV_SAMPLE_FMT_S16, channel_layout, sample_rate,
        params->frame_size > 0 ? params->frame_size : 1024);
#endif

    int bytes_per_sample = av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
    InitSound(channels, sample_rate, bytes_per_sample);
  } while (0);

  PostThreadMessage(kUIThreadId, UI_THREAD_CALLBACK,
                    static_cast<WPARAM>(UI_CREATE_WINDOW),
                    reinterpret_cast<LPARAM>(this));
}

void BeeWindowsPlayer::on_play()
{
  if (ds_buffer_ != nullptr) {
    audio_write_cursor_ = -1;
    ds_buffer_->Play(0, 0, DSBPLAY_LOOPING);
  }
}

void BeeWindowsPlayer::on_pause()
{
  if (ds_buffer_ != nullptr)
    ds_buffer_->Stop();
}

void BeeWindowsPlayer::on_video(AVFrame* frame)
{
  if (frame->width == 0 || frame->height == 0)
    return;

  constexpr int max_width = 1024, max_height = 768;

  int width  = min(max_width, max_height * frame->width / frame->height);
  int height = min(max_height, max_width * frame->height / frame->width);

  {
    std::lock_guard<std::mutex> lck(draw_buffer_mtx_);

    if (width_ != width || height_ != height) {
      if (draw_buffer_size_ < width * height * 4)
        draw_buffer_.reset(new uint8_t[width * height * 4]);

      width_ = width;
      height_ = height;
      need_resize_ = true;
    }
  }

  sws_ctx_ = sws_getCachedContext(sws_ctx_, frame->width, frame->height,
      (AVPixelFormat)frame->format, width, height, AV_PIX_FMT_BGRA,
      /*SWS_FAST_BILINEAR*/SWS_POINT, nullptr, nullptr, nullptr);
  if (nullptr == sws_ctx_) return;

  AVFrame picture;
  int err = av_image_fill_arrays(picture.data, picture.linesize,
      draw_buffer_.get(), AV_PIX_FMT_BGRA, width, height, 1);
  if (err < 0) return;

  err = sws_scale(sws_ctx_, (const uint8_t* const*)frame->data,
      frame->linesize, 0, frame->height, picture.data, picture.linesize);

  InvalidateRect(window_, NULL, TRUE);
}

void BeeWindowsPlayer::on_audio(AVFrame* frame)
{
  assert(ds_buffer_);

  for (resample_.InputFrame(frame);; ) {
    BeeFFmpegUtils::AutoFrame frame = resample_.GetFrame();
    if (!frame) break;

    DWORD play_cursor = 0, write_cursor = 0;
    HRESULT r = ds_buffer_->GetCurrentPosition(&play_cursor, &write_cursor);
    if (DS_OK != r) return;

    if (audio_write_cursor_ == -1) {
      audio_write_cursor_ = write_cursor;
    } else if (write_cursor > audio_write_cursor_) {
      assert(play_cursor > audio_write_cursor_ ||
             audio_write_cursor_ - play_cursor < BUFFERNOTIFYSIZE ||
             AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE +
             play_cursor - audio_write_cursor_ < BUFFERNOTIFYSIZE);
      assert(play_cursor < audio_write_cursor_ ||
             play_cursor - audio_write_cursor_ < BUFFERNOTIFYSIZE ||
             AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE +
             audio_write_cursor_ - play_cursor < BUFFERNOTIFYSIZE);
      DWORD diff = write_cursor - audio_write_cursor_;
      if (diff < BUFFERNOTIFYSIZE) audio_write_cursor_ = write_cursor;
    } else {
      assert(play_cursor > audio_write_cursor_ ||
             audio_write_cursor_ - play_cursor < BUFFERNOTIFYSIZE ||
             AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE +
             play_cursor - audio_write_cursor_ < BUFFERNOTIFYSIZE);
      assert(play_cursor < audio_write_cursor_ ||
             play_cursor - audio_write_cursor_ < BUFFERNOTIFYSIZE ||
             AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE +
             audio_write_cursor_ - play_cursor < BUFFERNOTIFYSIZE);
      DWORD diff = AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE +
                   write_cursor - audio_write_cursor_;
      if (diff < BUFFERNOTIFYSIZE) audio_write_cursor_ = write_cursor;
    }

    int buffer_size = av_samples_get_buffer_size(nullptr,
#if LIBAVUTIL_VERSION_MAJOR < 57
        frame->channels,
#else
        frame->ch_layout.nb_channels,
#endif
        frame->nb_samples,
        (AVSampleFormat)frame->format, 1);

    constexpr size_t extra_size = BUFFERNOTIFYSIZE;

    for (const uint8_t* ptr = frame->data[0]; buffer_size > 0; ) {
      uint8_t *dst1_buf = nullptr, *dst2_buf = nullptr, *extra_buf;
      DWORD dst1_size = 0, dst2_size = 0;
      HRESULT r = ds_buffer_->Lock(audio_write_cursor_,
                                   buffer_size + extra_size,
                                  (void**)&dst1_buf, &dst1_size,
                                  (void**)&dst2_buf, &dst2_size, 0);
      if (DS_OK != r) break;

      assert((dst1_size + dst2_size) == buffer_size + extra_size);

      if (dst1_buf != nullptr && dst1_size > 0) {
        DWORD copy_size = min((DWORD)buffer_size, dst1_size);
        assert(audio_write_cursor_ >= play_cursor ||
               audio_write_cursor_ + copy_size < play_cursor);
        memcpy(dst1_buf, ptr, copy_size);
        ptr += copy_size;
        buffer_size -= copy_size;
        extra_buf = dst1_buf + copy_size;
        audio_write_cursor_ += copy_size;
        /* 多填充一些静音数据，避免爆音 */
        if (copy_size < dst1_size) memset(extra_buf, 0, dst1_size - copy_size);
      }
      if (dst2_buf != nullptr && dst2_size > 0) {
        DWORD copy_size = min((DWORD)buffer_size, dst2_size);
        assert(copy_size < play_cursor);
        memcpy(dst2_buf, ptr, copy_size);
        ptr += copy_size;
        buffer_size -= copy_size;
        extra_buf = dst2_buf + copy_size;
        audio_write_cursor_ += copy_size;
        /* 多填充一些静音数据，避免爆音 */
        if (copy_size < dst2_size) memset(extra_buf, 0, dst2_size - copy_size);
      }

      audio_write_cursor_ %= AUDIO_BUFFERS_NB * BUFFERNOTIFYSIZE;

      ds_buffer_->Unlock(dst1_buf, dst1_size, dst2_buf, dst2_size);
    }
  }
}

void BeeWindowsPlayer::on_stop()
{
  if (ds_buffer_ != NULL) {
    ds_buffer_->Stop();
    ds_buffer_->Release();
    ds_buffer_ = NULL;
  }

  if (ds_ctx_ != NULL) {
    ds_ctx_->Release();
    ds_ctx_ = NULL;
  }

  if (sws_ctx_ != nullptr) {
    InnerDeleter()(sws_ctx_);
    sws_ctx_ = nullptr;
  }

  PostThreadMessage(kUIThreadId, UI_THREAD_CALLBACK,
                    static_cast<WPARAM>(UI_DESTROY_WINDOW),
                    reinterpret_cast<LPARAM>(this));
}

void BeeWindowsPlayer::on_error(
  const char* file, int line, const char* prefix, const char* err)
{
  bee::logger::log(bee::logger::BEE_ERROR, file, line, "%s %s", prefix, err);
}

static void FFmpegLogCallback(void *ptr, int level, const char *fmt, va_list vl)
{
  if (level > av_log_get_level())
    return;

  AVClass* avc = ptr ? *(AVClass **)ptr : NULL;
  const char* module = avc ? avc->item_name(ptr) : "ffmpeg";

  char buffer[1024] = {0};
  int n = vsnprintf(buffer, sizeof(buffer) - 1, fmt, vl);
  if (n <= 0) return;
  buffer[n] = '\0';

  const char* msg = buffer;
  for (int i = 0; i < n; ++i) {
    if (buffer[i] == '\r' || buffer[i] == '\n') {
      buffer[i] = '\0';
    } else if (buffer[i] != '\0') {
      continue;
    }
    if (msg < buffer + i) {
      switch(level) {
        case AV_LOG_TRACE:  BEE_LOG_DEBUG("%s %s", module, msg); break;
        case AV_LOG_DEBUG:  BEE_LOG_DEBUG("%s %s", module, msg); break;
        case AV_LOG_INFO:    BEE_LOG_INFO("%s %s", module, msg); break;
        case AV_LOG_WARNING: BEE_LOG_WARN("%s %s", module, msg); break;
        case AV_LOG_ERROR:  BEE_LOG_ERROR("%s %s", module, msg); break;
        case AV_LOG_FATAL:  BEE_LOG_ERROR("%s %s", module, msg); break;
        default: break;
      }
    }
    msg = buffer + i + 1;
  }
}

int main(int argc, char *argv[])
{
  //av_log_set_level(AV_LOG_TRACE);
  //av_log_set_level(AV_LOG_DEBUG);
  av_log_set_level(AV_LOG_INFO);
  //av_log_set_level(AV_LOG_ERROR);
  av_log_set_callback(FFmpegLogCallback);

  //avdevice_register_all();

  bee_logger_init(9, nullptr);
  bee_env_init("{\"uid\":\"abcdefg\"}");

  auto player = bee::net::BeeAVPlayer::Create<BeeWindowsPlayer>();

  bool ok = player->open(
    //"https://hot.vrs.sohu.com/vrs_drm.action?vid=6602631&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI"
      "http://10.19.17.148:888/seek.mp4"
  );

  if (!ok) return -1;

  kUIThreadId = GetCurrentThreadId();

  WNDCLASSEX wcex = { sizeof(WNDCLASSEX) };
  wcex.style = CS_DBLCLKS;
  wcex.hInstance = GetModuleHandle(NULL);
  wcex.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wcex.hCursor = LoadCursor(NULL, IDC_ARROW);
  wcex.lpfnWndProc = &BeeWindowsPlayer::WndProc;
  wcex.lpszClassName = kClassName;

  if (RegisterClassEx(&wcex) == NULL) {
    BEE_LOG_ERROR("RegisterClassEx failed with error %ld", GetLastError());
    return -1;
  }

  player->play();

  for (bool terminate = false; !terminate; ) {
    MSG msg;
    BOOL gm = GetMessage(&msg, NULL, 0, 0);
    if (gm == 0 || gm == -1)
      break;
    if (msg.message == UI_THREAD_CALLBACK) {
      switch (static_cast<int>(msg.wParam)) {
      case UI_CREATE_WINDOW:
        reinterpret_cast<BeeWindowsPlayer*>(msg.lParam)->CreateUI();
        break;
      case UI_DESTROY_WINDOW:
        terminate = true;
        break;
      }
    } else {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }
  }

  bee_env_cleanup();

  return 0;
}
