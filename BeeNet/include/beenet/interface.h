#ifndef _BEE_INTERFACE_H_INCLUDED
#define _BEE_INTERFACE_H_INCLUDED

#include <sys/types.h>

#ifdef __cplusplus
extern "C"  {
#endif

//#if defined _WIN32 || defined __CYGWIN__
//# define BEEAPI __declspec(dllexport) WINAPI
//#elif __GNUC__ >= 4
//# define BEEAPI __attribute__ ((visibility ("default")))
//#else
//# define BEEAPI
//#endif

const char * bee_version();

/*
 * 初始化日志回调函数
 * level:
 *     打印日志详细程度的级别，高于该详细级别的日志不打印。
 * logger:
 *     日志回调函数，系统有打印日志的需求时会调用，不需要处理
 *     系统的日志可以置为NULL，该回调具有全局唯一性，多次设置
 *     时，仅最后一次设置生效。
 */
void bee_logger_init(int level, //-1=NONE, 0=FATAL, 1=ERROR, 2=WARN
                                // 3=INFO, 4=DEBUG, 5=TRACE
                     void(*logger)(const char *pri,  // "FATAL" or
                                                     // "ERROR" or
                                                     // "WARN"  or
                                                     // "INFO"  or
                                                     // "DEBUG" or
                                                     // "TRACE"
                                   const char *name, // project name
                                                     // or file name
                                   const char *message));

/*
 * 设置SDK全局配置
 * opaque_json:
 *     用来传递系统运行时需要的参数，json格式的字符串,建议用来传
 *     递一些需要全局保存的配置信息，例如用户ID，User-Agent。
 *     该函数可以在任何时候任何次数调用，如果有重复的配置，最后一
 *     次设置的生效。
 */
void bee_env_init(const char *opaque_json);

/*
 * 释放SDK环境资源
 * 可以不调用，表示程序退出时自动释放资源
 * 注意：一经调用所有的环境资源均被释放，全局作用
 */
void bee_env_cleanup(void);


/* 同步调用api */

int bee_open(const char *url, const char *opaque_json);

int bee_read(int fd, void *buffer, size_t buflen);

int bee_send(int fd, const char *message, size_t msglen);

/*
 * 返回值大于buflen表示缓冲区大小不够，此时不往缓冲区写入任何信息。
 * 返回值大于0小于等于buflen，此时缓冲区中内容为获取的信息。
 * 返回值小于0表示错误码。
 */
int bee_stat(int fd, void *buffer, size_t buflen);

off_t bee_seek(int fd, off_t offset, int whence);

int bee_close(int fd);


/* 异步调用api */

/*
 * onopen:
 *     open成功时回调该函数，fd大于0表示流的描述符，fd小于0表
 *     示执行出错错误码，不会出现等于0的情况。
 * userp:
 *     会在onrecv回调中传递的用户数据。
 *
 * open成功后必须调用close关闭，否则会产生资源占用。
 */
void bee_open_async(const char *url, const char *opaque_json,
  void (*onopen)(int fd, void *userp),
  void *userp);

/*
 * read_bytes:
 *     希望读取的字节数，系统缓存大于该给定字节数或者所有数据
 *     读取完毕会回调onrecv，该回调在系统调度线程中执行，请保
 *     证不能有阻塞，建议将数据扔给专门处理的线程处理。
 * onrecv:
 *     data为NULL时，err_or_len为0表示读取到数据结尾，不为0表
 *     示系统错误码，转换为int即是。
 *     data不为NULL时表示读取的数据，err_or_len表示读取数据的
 *     长度。
 */
void bee_read_async(int fd, size_t read_bytes,
  size_t (*onrecv)(const void *data, size_t err_or_len, void *userp),
  void *userp);

/*
 * message:
 *     发送交互信息给系统，比如在websocket交互中发送信息给服务
 ×     端，再比如在webrtc交互过程中发送关闭语音或者切换摄像头
 *     等命令。
 * onsent:
 *     系统处理完信息后告知调用者处理结果。
 *     err小于0时，表示执行错误码，其他表示执行成功（比如在某
 *     些应用中可以用来表示TransactionID）。
 */
void bee_send_async(int fd, const char *message, size_t msglen,
  void (*onsent)(int err, void *userp),
  void *userp);

/*
 * onstat:
 *     获取流的状态信息，普通的http以json格式返回status code以
 *     及response header。
 *     err_or_len大于0时，data表示返回状态信息字符串，字符串长
 *     度由err_or_len给出。
 *     err_or_len小于等于0时，表示执行错误码。
 */
void bee_stat_async(int fd,
  void (*onstat)(const void *data, int err_or_len, void *userp),
  void *userp);

/*
 * whence:
 *     SEEK_SET: offset的值表示相对于流的起始位置的偏移。
 *     SEEK_CUR: offset的值表示相对于流的当前位置的偏移，
 *               调用read后当前位置会随着已读取的字节往后移。
 *     SEEK_END: offset的值表示相对于流的结束位置的偏移，
 *               需要注意，通常在流没有开始读取时拿不到流的长
 *               度，从而无法给出结束位置，而返回失败。
 * onseek:
 *     err_or_off小于0表示系统错误码，转换为int即是，否则表示
 *     执行seek后当前位置相对于流开始位置的偏移量。
 */
void bee_seek_async(int fd, off_t offset, int whence,
  void (*onseek)(off_t err_or_off, void *userp),
  void *userp);

/*
 * onclose:
 *     error等于0表示close执行成功，小于0表示系统错误码，不会
 *     出现大于0的情况。
 *     无论error为何种值都不必再对fd做进一步处理。
 */
void bee_close_async(int fd,
  void (*onclose)(int error, void *userp),
  void *userp);

#ifdef __cplusplus
}
#endif

#endif // _BEE_INTERFACE_H_INCLUDED
