#include "beenet/interface.h"
#include <windows.h>
#include <stdio.h>
#include <array>

int test1(); //drm online download test
int test2(); //download file (split into multiple range requests)
int test3(); //normal download file (don't support seek)
int test4(); //seek test (don't split into mutlitple range requests)
int test5(); //seek test (split into multiple range requests)
int test6(); //custom request header
int test7(); //drm offline decode test (old format)
int test8(); //drm offline download test
int test9(); //drm offline decode test
int test10(); //get drm offline download url (old format)
int test11(); //drm offline file seek test (old format)
int test12(); //close immediately after open
int test13(); //test auto decompess
int test14(); //download & decrypt test for sohu encrypted m3u8
int test15(); //download by proxy
int test16(); //global proxy, will overriding by individual settings
int test17(); //live stream (endless), close actively
int test18(); //drmv3 test
int test19(); //unicom nofee support
int test20(); //get error code for http 404
int test21(); //tcp fast open

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
  //test4();
  //test5();
  //test6();
  //test7();
  //test8();
  //test9();
  //test10();
  //test11();
  //test12();
  //test13();
  //test14();
  //test15();
  //test16();
  //test17();
  //test18();
  //test19();
  //test20();
  test21();

  bee_env_cleanup();
  return 0;
}

int test1()
{
  int fd = bee_open(
    "https://hot.vrs.sohu.com/vrs_drm.action?vid=8385508&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI",
    "{\"player\":\"SOHUPLAYER\"}"
    /* 对于SOHU DRM视频（根据url自动识别）:
     * 1. 带player=SOHUPLAYER表示下载在线播放文件。
     * 2. 其它的情况表示下载离线文件。
     */
  );
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  FILE *file; fopen_s(&file, "out1.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test2()
{
  int fd = bee_open(
    "http://data.vod.itc.cn/sdl/NTRrwGzOLSCiAHXqtZhlAjVkTJCfb6zPU5jj9Q853qy25MQdl26h1HAZJ5nZZMut1a7iqnnMttR1oxYyJDfolznve1PK/wI7KIp.mp4",
    "{\"player\":\"SOHUPLAYER\"}"
    /* 走分块下载逻辑的条件（下面条件满足任意一条即可）:
     * 1. url为data.vod.itc.cn下的非.ts后缀文件。
     * 2. 参数中包括player属性，但没有chunked属性。
     * 3. 参数中包括player和chunked属性，且chunked值不为0。
     */
  );
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  FILE *file; fopen_s(&file, "out2.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test3()
{
  int fd = bee_open(
    "http://10.19.17.148:888/test.mp4",
    nullptr /* 走非分块下载且不支持seek逻辑的条件（下面条件满足任意一条即可）：
             * 1. url为data.vod.itc.cn下的.ts文件。
             * 2. 非data.vod.itc.cn下的，且参数中不带player属性。
             */
  );
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  FILE *file; fopen_s(&file, "out3.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, file);
    Sleep(10); //模拟读取速度小于下载速度情况，看是否触发下载暂停逻辑
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test4()
{
  int fd = bee_open(
    "http://10.19.17.148:888/test.mp4",
    "{\"player\":\"SOHUPLAYER\", \"chunked\":0}"
    /* 走非分块下载但支持seek逻辑的条件（下面条件同时满足）：
     * 1. 非data.vod.itc.cn下的文件下载。
     * 2. 参数中包括player属性。
     * 3. 参数中包括chunked属性，且属性值为0。
     */
  );
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  off_t off = bee_seek(fd, 3943750, 0);
  if (off < -65535) {
    int tmp = -off;
    fprintf(stderr, "xxxx seek result: %.*s\n", 4, (const char*)&tmp);
    bee_close(fd);
    return -1;
  } else if (off < 0) {
    fprintf(stderr, "xxxx seek result: %ld\n", off);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx seek result: %ld\n", off);

  char buffer[1024*1024];

  for (int loop = 0; loop < 20; ++loop) {
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      bee_close(fd);
      return -1;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      bee_close(fd);
      return -1;
    }
  }

  off = bee_seek(fd, 10, 0);
  if (off < -65535) {
    int tmp = -off;
    fprintf(stderr, "xxxx seek result: %.*s\n", 4, (const char*)&tmp);
    bee_close(fd);
    return -1;
  } else if (off < 0) {
    fprintf(stderr, "xxxx seek result: %ld\n", off);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx seek result: %ld\n", off);

  int read_bytes = bee_read(fd, buffer, sizeof(buffer));
  if (read_bytes < -65535) {
    int tmp = -read_bytes;
    fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
    bee_close(fd);
    return -1;
  } else if (read_bytes < 0) {
    fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx read result: %d\n", read_bytes);

  bee_close(fd);
  return 0;
}

int test5()
{
  int fd = bee_open("https://data.vod.itc.cn/sdl/NTRrwGzOLSCiAHXqtZhlAjVkTJCfb6zPU5jj9Q853qy25MQdl26h1HAZJ5nZZMut1a7iqnnMttR1oxYyJDfolznve1PK/wI7KIp.mp4", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  off_t off = bee_seek(fd, 3943750, 0);
  if (off < -65535) {
    int tmp = -off;
    fprintf(stderr, "xxxx seek result: %.*s\n", 4, (const char*)&tmp);
    bee_close(fd);
    return -1;
  } else if (off < 0) {
    fprintf(stderr, "xxxx seek result: %ld\n", off);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx seek result: %ld\n", off);

  char buffer[1024*1024];

  for ( ;; ) {
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
  }

  off = bee_seek(fd, 10, 0);
  if (off < -65535) {
    int tmp = -off;
    fprintf(stderr, "xxxx seek result: %.*s\n", 4, (const char*)&tmp);
    bee_close(fd);
    return -1;
  } else if (off < 0) {
    fprintf(stderr, "xxxx seek result: %ld\n", off);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx seek result: %ld\n", off);

  int read_bytes = bee_read(fd, buffer, sizeof(buffer));
  if (read_bytes < -65535) {
    int tmp = -read_bytes;
    fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
    bee_close(fd);
    return -1;
  } else if (read_bytes < 0) {
    fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx read result: %d\n", read_bytes);

  bee_close(fd);
  return 0;
}

int test6()
{
  int fd = bee_open("https://testgslb.tv.sohu.com/m3u8?&start=134.72&end=162.44&k=hWODtfkIlB6OfOcOfh6HR88ISkm4k5Dtm1mX5wm4ZvA9fBzSkdytHrChRYCzSPWsisIWhXs5G1S0TPcWGdswm1UoTbcWhyS0pviNF2CfDoGNh24r&a=hWqbzHJUhWqFjfaptUJlzSwGqSwdqLNGoSkGoSxVoSw3oSoihlqzE5aSalrIgTXLP6vRWmWvfJNRWBdCNevsDOvvf4fBW6xFT8vGf4f4MEkMRTxe8eb7yBoVqTPcWJAsRY1OWBo7oB2svmeCNF2sWB6sWhyOfOWtfhdsWJvtvm8I9kIWr&sig=1Qs6DSq10BLq3g1K-FJjG57IRbZ8p-vQ", "{\"custom_headers\":[\"X-Content-Type: json\"]}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, stdout);
  }

  bee_close(fd);
  return 0;
}

int test7()
{
  int fd = bee_open("sdr:old_drm.mp4", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  FILE *file; fopen_s(&file, "out7.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test8()
{
  int fd = bee_open("https://hot.vrs.sohu.com/vrs_drm.action?vid=8385508&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  FILE *file; fopen_s(&file, "out8.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test9()
{
  int fd = bee_open("sdr:out8.tmp", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  FILE *file; fopen_s(&file, "out9.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
     }
    fwrite(buffer, read_bytes, 1, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test10()
{
  int fd = bee_open("https://hot.vrs.sohu.com/vrs_drm.action?vid=8385508&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI", "{\"offline_url\":true}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char buf[128], *new_buf = nullptr, *stat_buf = buf;
  int len = bee_stat(fd, buf, sizeof(buf));
  if (len > sizeof(buf)) {
    new_buf = (char*)malloc(len);
    if (new_buf == nullptr) return -ENOMEM;
    if (len != bee_stat(fd, new_buf, len)) {
      fprintf(stderr, "xxx what the hell\n");
      return -1;
    }
    stat_buf = new_buf;
  }

  if (len < -65535) {
    int tmp = -len;
    fprintf(stderr, "xxxx error: %.*s\n", 4, (const char*)&tmp);
  } else if (len < 0) {
    fprintf(stderr, "xxxx error code: %d\n", len);
  }

  //{"url":"https:\/\/621-5-3.vod.tv.itc.cn\/sohu\/v1\/TmwGoAIsWBvHMY6ComEmPedDD49XWm8NotksgJy2bJXUyYbSoO2A0S4SoLc7ZMcUwmP3RD1m0Db7NGNVRhv4gMy4ymK.mp4?k=7MASOp&p=jWlvzS1m0pk3op1Wj9lvz956sUJlOWXWOWlNOSCuoSwmTmwio6INfTxmqTo6MKWlDOAtoedGgJ63fVeF5m47fFo70ScAZMK70YoANh2svmPdRD1SqMvAZMAAyOo20O2sWDAsfhvXWDyOfY6OY&r=TUJAtEIBh8NtgGN6yTA2yp8ihJ1Dq6wdNtwFPTXLfhNCqY6DqAvv8Vcs8Mv3WLyDyMemqhyOgtXiqMX6bEw6D8s1btW6qE9BfVdWqVsFfm9UbGbMyTe704Ei8tPMD8PWb6wGRTyD0tomPmWI5ahaRqgtpFhO3lhXWIBeGNVgT8tNLvm08KsD6sXo6x4Wp4WW2vbypkUqSeDhLNehFeeDpAg8LCihA0RetfRbLfvT816eJ6vfM1tNGAVq2y6PMWGDT4v8MsmWm4ChVeXqLEVPTK1bB6iWLPReSWmu8xWyBbvzJ66DKE3gKCifpxBbt81DM0b0JyNN6XXM8s1NVdsft0IRYBapOO9lwCcajh4llg9WFHJS1i4U3y4UOHolFb&q=OpCAhW7IWhodRDbswmfCyY2sWh1HfFWHZYWHfOvS0F2OZh1sZhvsZhoURDvOWJoUZDJ&nid=621"}
  fprintf(stdout, "xxxx stat: %.*s\n", len, stat_buf);

  if (new_buf != nullptr) free(new_buf);

  bee_close(fd);
  return 0;
}

int test11()
{
  int fd = bee_open("sdr:old_drm.mp4", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  off_t off = bee_seek(fd, 3943750, 0);
  if (off < -65535) {
    int tmp = -off;
    fprintf(stderr, "xxxx seek result: %.*s\n", 4, (const char*)&tmp);
    bee_close(fd);
    return -1;
  } else if (off < 0) {
    fprintf(stderr, "xxxx seek result: %ld\n", off);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx seek result: %ld\n", off);

  off = bee_seek(fd, 10, 0);
  if (off < -65535) {
    int tmp = -off;
    fprintf(stderr, "xxxx seek result: %.*s\n", 4, (const char*)&tmp);
    bee_close(fd);
    return -1;
  } else if (off < 0) {
    fprintf(stderr, "xxxx seek result: %ld\n", off);
    bee_close(fd);
    return -1;
  }

  fprintf(stderr, "xxxx seek result: %ld\n", off);

  bee_close(fd);
  return 0;
}

int test12()
{
  int fd = bee_open("https://www.sina.com.cn", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  bee_close(fd);
  return 0;
}

int test13()
{
  int fd = bee_open("https://www.sohu.com", "{\"accept_encoding\":\"*/*\"}");
  //int fd = bee_open("https://www.sohu.com", "{\"accept_encoding\":null}");
  //int fd = bee_open("https://www.sohu.com", nullptr);
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  FILE *file; fopen_s(&file, "out13.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, 1, read_bytes, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test14()
{
  int fd = bee_open(
    //"https://hot.vrs.sohu.com/m3u8v3/9269596_4944691168142_2470817.m3u8?plat=14&ssl=1&ca=2&cv=6.23.3&uid=558492866&prod=ifox&pg=5&plat=14&pt=1&qd=8001&playType=p2p",
    "https://uat-hot.vrs.sohu.com/drmv3/9265458_4940842204559_2476779.m3u8?plat=6&ssl=1&gid=x0107402101019283ada6940500024225476cbc70724&uid=SV_jTCiTsltAw6o_ihouY68zq3LQ2OXhEeKeKmvbJhfpXdP6AD0gt5a-xSFh5SvNhh1fc2I8qxrytLyv3wN5k3eIPjOaE3LjlPbBG5eMulzfY8&pt=5&prod=app&pg=1&sver=10.0.96&cv=10.0.96&qd=93&ca=3&vid=9265450&player=2.0",
    nullptr
  );
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, 1, read_bytes, stdout);
  }

  bee_close(fd);
  return 0;
}

int test15()
{
  //int fd = bee_open("https://google.com", "{\"proxy\":\"http://127.0.0.1:8888\"}");
  //int fd = bee_open("https://google.com", "{\"proxy\":\"http://user:pass@127.0.0.1:8888\"}");
  //int fd = bee_open("https://google.com", "{\"proxy\":\"http://127.0.0.1:8888\",\"proxy_user\":\"xxx\",\"proxy_pass\":\"xxx\"}");
  int fd = bee_open("https://google.com", "{\"proxy\":\"https://127.0.0.1:4443\",\"untrust_proxy\":true}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, 1, read_bytes, stdout);
  }

  bee_close(fd);
  return 0;
}

int test16()
{
  //bee_env_init("{\"proxy\":\"http://127.0.0.1:8888\"}");
  //bee_env_init("{\"proxy\":\"http://user:pass@127.0.0.1:8888\"}");
  //bee_env_init("{\"proxy\":\"http://127.0.0.1:8888\",\"proxy_user\":\"xxx\",\"proxy_pass\":\"xxx\"}");
  bee_env_init("{\"proxy\":\"https://127.0.0.1:4443\"}");

  //int fd = bee_open("https://google.com", nullptr);
  int fd = bee_open("https://google.com", "{\"untrust_proxy\":true}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, 1, read_bytes, stdout);
  }

  bee_close(fd);
  return 0;
}

int test17()
{
  int fd = bee_open("https://v-ngb.qf.56.com/live/7215974_1735560312527.flv", "{\"player\":\"SOHUPLAYER\"}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  for (int loop = 0 ; loop < 20; ++loop) {
    char buffer[64*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fprintf(stdout, "xxxx recv %d bytes\n", read_bytes);
    if (read_bytes == 0) break;
  }

  bee_close(fd);
  return 0;
}

int test18()
{
  int fd = bee_open("http://data.vod.itc.cn/drmv3?k=Xilmz9FujZOAXAOdXm3Yk5rWjRrIWJNsvmN2ZMNB0OoA0S4clB6sfDcsWG1Hb4NvWpkFDTXDy6yVgKoCuEvD8KeFbhXUyYbS0pbcWDoGyG2sWYXs5GdOvm6AZDN4RY6S0psdyF2twm1BqVPcNT17wmfdRDWS0tbdySbcWF1HfFoAgmPcWFyHff&a=j9lvzSxmqSaFOSjFT9xAq9Pgqfomq6C70pOlTSX30pwiO9si0pqvs9s7hWqbzHJUhWqFjfaptUJlzSwdoSw3oSNGopwGqSkVoSrGoSkihRODOpCmqLsA0Sv7hRYRzSwWOHllzSr&sig=F35JgIhure_Q1-PQR0pEJECxOkKJ3yFk", "{\"player\":\"SOHUPLAYER\"}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  char stat_buf[1024];
  int len = bee_stat(fd, stat_buf, sizeof(stat_buf));
  fprintf(stderr, "xxxx stat result: %d\n", len);
  if (len > 0 && (size_t)len <= sizeof(stat_buf))
    fprintf(stderr, "xxxx stat: %.*s\n", len, stat_buf);

  FILE *file; fopen_s(&file, "out18.tmp", "w");
  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
    fwrite(buffer, read_bytes, 1, file);
  }
  fclose(file);

  bee_close(fd);
  return 0;
}

int test19()
{
  int fd = bee_open(
      //"https://hot.vrs.sohu.com/vrs_drm.action?vid=8385508&mkey=TE4z8DCe1yWuMdfl0m3VMHmAyuxtDSVI",
      //"https://data.vod.itc.cn/sdl/NTRrwGzOLSCiAHXqtZhlAjVkTJCfb6zPU5jj9Q853qy25MQdl26h1HAZJ5nZZMut1a7iqnnMttR1oxYyJDfolznve1PK/wI7KIp.mp4",
      "http://data.vod.itc.cn/drmv3?k=Xilmz9FujZOAXAOdXm3Yk5rWjRrIWJNsvmN2ZMNB0OoA0S4clB6sfDcsWG1Hb4NvWpkFDTXDy6yVgKoCuEvD8KeFbhXUyYbS0pbcWDoGyG2sWYXs5GdOvm6AZDN4RY6S0psdyF2twm1BqVPcNT17wmfdRDWS0tbdySbcWF1HfFoAgmPcWFyHff&a=j9lvzSxmqSaFOSjFT9xAq9Pgqfomq6C70pOlTSX30pwiO9si0pqvs9s7hWqbzHJUhWqFjfaptUJlzSwdoSw3oSNGopwGqSkVoSrGoSkihRODOpCmqLsA0Sv7hRYRzSwWOHllzSr&sig=F35JgIhure_Q1-PQR0pEJECxOkKJ3yFk",
      "{\"nofee\": {\"partner\": \"unicom\", \"key\": \"SOHUKEY\", \"host_port\": \"116.162.160.162:809/if5ax\", \"params\": \"apptype=app&userid=15693808130&spid=21126&pid=8031006300&preview=1&portalid=300&spip=data.vod.itc.cn&spport=80&ugpid=1155&tradeid=1d01bf0510b24c7d82a6353272a97a92&lsttm=20231121044728\"}, \"player\": \"SOHUPLAYER\"}");
  if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  fprintf(stderr, "xxxx open result: %d\n", fd);

  for ( ;; ) {
    char buffer[1024*1024];
    int read_bytes = bee_read(fd, buffer, sizeof(buffer));
    if (read_bytes == 0) break;
    if (read_bytes < -65535) {
      int tmp = -read_bytes;
      fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
      break;
    } else if (read_bytes < 0) {
      fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
      break;
    }
  }

  bee_close(fd);
  return 0;
}

int test20()
{
  int fd = bee_open(
    "https://www.baidu.com/test/nonexists.html",
    "{\"player\":\"SOHUPLAYER\"}"
  );
  if (fd + 65536 == 404) {
    fprintf(stderr, "xxxx open result: http respond 404\n");
  } else if (fd < -65535) {
    int tmp = -fd;
    fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
    return -1;
  } else if (fd < 0) {
    fprintf(stderr, "xxxx open result: %d\n", fd);
    return -1;
  }

  bee_close(fd);
  return 0;
}

int test21()
{
  bee_env_init("{\"tcp_fastopen\":true}");

  for (int timeout : std::array{10,120,0}) {
    int fd = bee_open("https://757-9.vod.tv.itc.cn/nonexists", "{\"verbose\":true}");
    if (fd < -65535) {
      int tmp = -fd;
      fprintf(stderr, "xxxx open result: %.*s\n", 4, (const char*)&tmp);
      return -1;
    } else if (fd < 0) {
      fprintf(stderr, "xxxx open result: %d\n", fd);
      return -1;
    }

    fprintf(stderr, "xxxx open result: %d\n", fd);

    for ( ;; ) {
      char buffer[1024*1024];
      int read_bytes = bee_read(fd, buffer, sizeof(buffer));
      if (read_bytes == 0) break;
      if (read_bytes < -65535) {
        int tmp = -read_bytes;
        fprintf(stderr, "xxxx recv result: %.*s\n", 4, (const char *)&tmp);
        break;
      } else if (read_bytes < 0) {
        fprintf(stderr, "xxxx recv result: %d\n", read_bytes);
        break;
      }
      fwrite(buffer, read_bytes, 1, stdout);
    }

    bee_close(fd);

    Sleep(timeout);
  }

  return 0;
}
