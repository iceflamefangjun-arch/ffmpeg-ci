/*
   Copyright (C) 2010-2016 Yuan Jun <uanjun@hotmail.com>

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef IO_BUFFER_H_INCLUDED
#define IO_BUFFER_H_INCLUDED

#include <sys/types.h>
#include <inttypes.h>
#include <stdarg.h>
#include <assert.h>

namespace bee {
namespace net {

template<class T> class io_buffer_view;

class io_buffer {
template<class T> friend class io_buffer_view;
private:
  // return false means out of memory
  typedef bool (*threshold_check_callback)(const io_buffer &iob, size_t expect);

public:
  explicit io_buffer(const char *buf, size_t size);
  explicit io_buffer(char *buf, size_t size);
  explicit io_buffer(size_t size=4096, threshold_check_callback callback=nullptr);

  ~io_buffer();

  io_buffer & operator =(io_buffer &&from);

  bool empty() const { return (m_data_off == m_curr_off); }

  //此处分配的内存必须立即使用，否则此内存可能会在后面被重新分配。
  char * alloc(size_t size);

  //尽量使用此模板alloc函数，避免上面非模板alloc函数的问题。
  template<class T> io_buffer_view<T> alloc() {
    alloc(sizeof(T));
    auto tmp = io_buffer_view<T>(this, m_data_off);
    m_data_off += sizeof(T);
    return tmp;
  }

  const char * ptr() const noexcept {
    assert(m_data_ptr != nullptr || m_curr_off == 0);
    return (m_data_ptr + m_curr_off);
  }
  const char * end() const noexcept {
    assert(m_data_ptr != nullptr);
    return (m_data_ptr + m_data_off);
  }
  size_t size() const noexcept {
    return (m_data_off - m_curr_off);
  }
  size_t capacity() const noexcept {
    return m_buf_size;
  }
  io_buffer & release(size_t n);  // increase read point by n
  io_buffer & chop();  // decrease write point by 1
  io_buffer & chomp();  // 去掉尾部的\r\n
  io_buffer & clear();  // clear write & read point

  size_t stuff(size_t n);
  size_t put_byte(int8_t val);
  size_t put_word(int16_t val);
  size_t put_int32(int32_t val);
  size_t put_int64(int64_t val);
  size_t concat(void const *string, size_t len);
  size_t put_vstring(char const *format, va_list ap);
  size_t put_string(char const *format, ...);
  int8_t get_byte();
  int16_t get_word();
  int32_t get_int32();
  int64_t get_int64();
  bool get_byte(int8_t *pval);
  bool get_word(int16_t *pval);
  bool get_int32(int32_t *pval);
  bool get_int64(int64_t *pval);
  int get_line(char const seperator[]="\n", int n=2);

private:
  io_buffer(const io_buffer &from) = delete;
  io_buffer & operator =(const io_buffer &from) = delete;

  threshold_check_callback threshold_callback;
  char *m_data_ptr;
  size_t m_buf_size; // 分配的缓存大小
  size_t m_data_off; // 当前写入位置偏移
  size_t m_curr_off; // 当前读出位置偏移
  size_t m_temp_off; // get_line上次行检测的偏移
};

template<class T> class io_buffer_view {
friend class io_buffer;
public:
  io_buffer_view(io_buffer_view &&from) : iob_(from.iob_), offset_(from.offset_) {}
  ~io_buffer_view() = default;
  T * get() const {
    assert(offset_ < iob_->m_buf_size);
    return reinterpret_cast<T*>(iob_->m_data_ptr + offset_);
  }
  size_t size() const { return sizeof(T); }
  T * operator ->() const { return get(); }
  T & operator  *() const { return (*get()); }
private:
  explicit io_buffer_view(const io_buffer *p, size_t off) : iob_(p), offset_(off) {}
  io_buffer_view(const io_buffer_view &from) = delete;
  io_buffer_view & operator =(const io_buffer_view &from) = delete;
  const io_buffer *iob_;
  const size_t offset_;
};

inline uint8_t EncodeInt8(uint8_t val)
{
  return val;
}

inline uint16_t EncodeInt16(uint16_t val)
{
  uint8_t tmp[2];
  tmp[0] = (val >> 8) & 0xff;
  tmp[1] =  val       & 0xff;
  return (*((uint16_t*)tmp));
}

inline uint32_t EncodeInt32(uint32_t val)
{
  uint8_t tmp[4];
  tmp[0] = (val >> 24) & 0xff;
  tmp[1] = (val >> 16) & 0xff;
  tmp[2] = (val >> 8 ) & 0xff;
  tmp[3] =  val        & 0xff;
  return (*((uint32_t*)tmp));
}

inline uint64_t EncodeInt64(uint64_t val)
{
  uint8_t tmp[8];
  tmp[0] = (val >> 56) & 0xff;
  tmp[1] = (val >> 48) & 0xff;
  tmp[2] = (val >> 40) & 0xff;
  tmp[3] = (val >> 32) & 0xff;
  tmp[4] = (val >> 24) & 0xff;
  tmp[5] = (val >> 16) & 0xff;
  tmp[6] = (val >> 8 ) & 0xff;
  tmp[7] =  val        & 0xff;
  return (*((uint64_t*)tmp));
}

inline uint8_t DecodeInt8(const uint8_t *val)
{
  return (*val);
}

inline uint16_t DecodeInt16(const uint8_t *val)
{
  uint16_t tmp =     val[0];
  tmp = (tmp << 8) | val[1];
  return tmp;
}

inline uint32_t DecodeInt32(const uint8_t *val)
{
  uint32_t tmp =     val[0];
  tmp = (tmp << 8) | val[1];
  tmp = (tmp << 8) | val[2];
  tmp = (tmp << 8) | val[3];
  return tmp;
}

inline uint64_t DecodeInt64(const uint8_t *val)
{
  uint64_t tmp =     val[0];
  tmp = (tmp << 8) | val[1];
  tmp = (tmp << 8) | val[2];
  tmp = (tmp << 8) | val[3];
  tmp = (tmp << 8) | val[4];
  tmp = (tmp << 8) | val[5];
  tmp = (tmp << 8) | val[6];
  tmp = (tmp << 8) | val[7];
  return tmp;
}

inline uint8_t DecodeInt8(uint8_t val)
{
  return val;
}

inline uint16_t DecodeInt16(uint16_t val)
{
  return DecodeInt16((uint8_t *)(&val));
}

inline uint32_t DecodeInt32(uint32_t val)
{
  return DecodeInt32((uint8_t *)(&val));
}

inline uint64_t DecodeInt64(uint8_t val)
{
  return DecodeInt64((uint8_t *)(&val));
}

} //namespace net
} //namespace bee

#endif /* IO_BUFFER_H_INCLUDED */
