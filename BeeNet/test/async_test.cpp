#include <cstdio>
#include <chrono>
#include <string>
#include "beenet/interface.hpp"
#include "beenet/asyncworker.hpp"

void test1(); //drm online download test
void test2(); //normal download json
void test3(); //normal download mp4
void test4(); //open and close many times
void test6(); //drm offline decode test (old format)
void test7(); //drm offline download test
void test8(); //drm offline decode test
void test9(); //close immediately after open
void test10(); //post message test
void test11(); //post mutipart message
void test12(); //download url who can't resolve domain
void test13(); //download url who response 204
void test14(); //heavy requests test

int main(int argc, char *argv[])
{
  bee_logger_init(9, nullptr);
  bee_env_init(
    "{"
      "\"uid\":\"abcdefg\""
    "}");

  //test1();
  //test2();
  //test3();
  test4();
  //test6();
  //test7();
  //test8();
  //test9();
  //test10();
  //test11();
  //test12();
  //test13();
  //test14();

  std::this_thread::sleep_for(std::chrono::seconds(10));

  bee_env_cleanup();
  return 0;
}


class MyDownload final : public bee::net::AsyncBeeStream {
public:
  MyDownload(const char *filename)
    : worker_(bee::net::AsyncBeeWorker::Create()),
      filename_(nullptr == filename ? "" : filename),
      out_(nullptr) {
  }

  ~MyDownload() {
    fprintf(stderr, "xxxx destroyed, %s\n", filename_.empty() ? "nil" : filename_.c_str());
  }

private:
  void on_open() {
    auto sp = std::static_pointer_cast<MyDownload>(self_);
    worker_->PostCmd([sp]()->void {
      if (sp->filename_.empty()) {
        sp->out_ = stdout;
      } else if (fopen_s(&sp->out_, sp->filename_.c_str(), "wb"); sp->out_ == nullptr) {
        fprintf(stderr, "xxxx (%d) can't open file for write, %s.\n", sp->fd(), strerror(errno));
        return sp->close();
      }
      fprintf(stderr, "xxxx (%d) open success, %s\n", sp->fd(), sp->filename_.c_str());
      sp->stat();
      sp->read(sizeof(sp->buffer_));
    });
  }

  size_t on_recv(const void *buffer, size_t length) {
    auto sp = std::static_pointer_cast<MyDownload>(self_);
    if (nullptr == buffer || 0 == length) {
      fprintf(stderr, "xxxx (%d) end of file\n", sp->fd());
      sp->close();
    } else {
      if (length > sizeof(buffer_)) length = sizeof(buffer_);
      memcpy(buffer_, buffer, length);
      worker_->PostCmd([sp,length]()->void {
        if (length != fwrite(sp->buffer_, 1, length, sp->out_)) {
          fprintf(stderr, "xxxx (%d) can't write file, %s.\n", sp->fd(), strerror(errno));
          return sp->close();
        }
        sp->stat();
        sp->read(sizeof(sp->buffer_));
      });
    }
    return length;
  }

  void on_stat(const void *buffer, int length) {
    assert(buffer != nullptr);
    auto sp = std::static_pointer_cast<MyDownload>(self_);
    std::string info(static_cast<const char *>(buffer), length);
    fprintf(stderr, "xxxx (%d) %s\n", sp->fd(), info.c_str());
  }

  void on_seek(off_t offset) {
    auto sp = std::static_pointer_cast<MyDownload>(self_);
    fprintf(stderr, "xxxx (%d) seek %ld\n", sp->fd(), offset);
  }

  void on_error(int error) {
    auto sp = std::static_pointer_cast<MyDownload>(self_);
    if (error < -65535) {
      int tmp = -error;
      fprintf(stderr, "xxxx (%d) error: %.*s\n", sp->fd(), 4, (const char *)&tmp);
    } else {
      fprintf(stderr, "xxxx (%d) error code: %d\n", sp->fd(), error);
    }
    sp->close();
  }

  void on_close(int error) {
    auto sp = std::static_pointer_cast<MyDownload>(self_);
    if (error < -65535) {
      int tmp = -error;
      fprintf(stderr, "xxxx (%d) closed, error %.*s, %s\n",
          sp->fd(), 4, (const char*)&tmp, sp->filename_.c_str());
    } else {
      fprintf(stderr, "xxxx (%d) closed, error %d, %s\n",
          sp->fd(), error, sp->filename_.c_str());
    }
    worker_->PostCmd([sp]()->void {
      if (nullptr != sp->out_ && sp->out_ != stdout) fclose(sp->out_);
    });
  }

  bee::net::AsyncBeeWorker *worker_;
  char buffer_[512*1024];
  std::string filename_;
  FILE *out_;
};

void test1()
{
  bee::net::AsyncBeeStream::Create<MyDownload>("out1.tmp")->open(
    "https://hot.vrs.sohu.com/vrs_drm.action?vid=8385508&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI",
    "{\"player\":\"SOHUPLAYER\"}"
  );
}

void test2()
{
  bee::net::AsyncBeeStream::Create<MyDownload>("out2.tmp")->open(
    //"https://data.vod.itc.cn/bee/push/889bb1875fbdd9f8f9201801a06d2abba7a2ec865a54b5d338b12186",
    //"https://hot.vrs.sohu.com/vrs_flash.action?vid=7147571&ver=1&ssl=1&pflag=pch5",
    "https://m.tv.sohu.com/cooperation/getBannerInfo?cateCode=101_B&callback=jsonpx1651305951286_80_2&_=1651305951286",
    nullptr
  );
}

void test3()
{
  bee::net::AsyncBeeStream::Create<MyDownload>("out3.tmp")->open(
    "https://data.vod.itc.cn/sdl/NTRrwGzOLSCiAHXqtZhlAjVkTJCfb6zPU5jj9Q853qy25MQdl26h1HAZJ5nZZMut1a7iqnnMttR1oxYyJDfolznve1PK/wI7KIp.mp4",
    nullptr
  );
}

void test4()
{
  for (int i = 0; i < 1000; ++i) {
    bee::net::AsyncBeeStream::Create<MyDownload>(nullptr)->open(
      "http://10.19.117.236/get",
      nullptr
    );
  }
}

void test6()
{
  bee::net::AsyncBeeStream::Create<MyDownload>("out6.tmp")->open(
    "sdr:old_drm.mp4",
    nullptr
  );
}

void test7()
{
  bee::net::AsyncBeeStream::Create<MyDownload>("out7.tmp")->open(
    "https://hot.vrs.sohu.com/vrs_drm.action?vid=8385508&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI",
    nullptr
  );
}

void test8()
{
  bee::net::AsyncBeeStream::Create<MyDownload>("out8.tmp")->open(
    "sdr:out7.tmp",
    nullptr
  );
}

void test9()
{
  for (int i = 0; i < 10; ++i) {
    auto tmp = bee::net::AsyncBeeStream::Create<MyDownload>(nullptr);
    tmp->open("https://www.sohu.com", nullptr);
    tmp->close();
  }
}

void test10()
{
  bee::net::AsyncBeeStream::Create<MyDownload>(nullptr)->open(
    //"http://10.19.117.225/test/xxxx",
    "http://10.19.117.236/post",
    "{\"post\":\"hello, it's me\"}"
  );
}

void test11()
{
  bee::net::AsyncBeeStream::Create<MyDownload>(nullptr)->open(
    "http://10.19.117.225/test/xxxx",
    "{\"form\":{"
      "\"text\":\"name begin without @ mean a text message\","
      "\"comment\":\"name begin with @ means filename\","
      "\"@testfile\":\"x.log\","
      "\"+@message\":\"if text message's name begin with @, should add + before first @\""
    "}}"
  );
}

void test12()
{
  bee::net::AsyncBeeStream::Create<MyDownload>(nullptr)->open(
    "https://sohu.irs01.com/irt?_iwt_UA=UA-sohu-000001&jsonp=_410RZ",
    nullptr
  );
}

void test13()
{
  bee::net::AsyncBeeStream::Create<MyDownload>(nullptr)->open(
    "https://z.m.tv.sohu.com/pv.gif?url=https%253A%252F%252Fm.tv.sohu.com%252F&refer=https%253A%252F%252Ftv.sohu.com%252F&uid=220408154616LXTZ&webtype=&screen=320x480&catecode=&pid=&vid=&tvid=&site=1&os=ios&platform=iphone&passport=&t=1651278492567&channeled=1213140001&oth=&cd=&isplay=1&MTV_SRC=11060001&sd=",
    nullptr
  );
}

void test14()
{
  for (int i = 0; i < 20; ++i) {
    test1();
    std::this_thread::sleep_for(std::chrono::seconds(20));
  }
}
