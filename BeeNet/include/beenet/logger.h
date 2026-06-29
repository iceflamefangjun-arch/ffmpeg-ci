#ifndef _BEE_LOGGER_H_
#define _BEE_LOGGER_H_

#include <sys/types.h>

namespace bee {
namespace logger {

enum : int {
  BEE_NONE  = -1,
  BEE_FATAL = 0,
  BEE_ERROR = 1,
  BEE_WARN  = 2,
  BEE_INFO  = 3,
  BEE_DEBUG = 4,
  BEE_TRACE = 5,
};

const char* get_log_level();
void set_log_level(int level);
void set_logger(void(*logger)(const char* level, const char* name, const char* msg));
void log(int level, const char* file_name, size_t line_number, const char* fmt, ...);

} //namespace logger
} //namespace bee

#define BEE_LOG(level, ...) do {               \
    bee::logger::log(bee::logger::BEE_##level, \
        __FILE__, __LINE__, __VA_ARGS__);      \
} while(0)

#define BEE_LOG_FATAL(...) BEE_LOG(FATAL, __VA_ARGS__)
#define BEE_LOG_ERROR(...) BEE_LOG(ERROR, __VA_ARGS__)
#define BEE_LOG_WARN(...)  BEE_LOG(WARN,  __VA_ARGS__)
#define BEE_LOG_INFO(...)  BEE_LOG(INFO,  __VA_ARGS__)
#define BEE_LOG_DEBUG(...) BEE_LOG(DEBUG, __VA_ARGS__)
#define BEE_LOG_TRACE(...) BEE_LOG(TRACE, __VA_ARGS__)

#endif // _BEE_LOGGER_H_
