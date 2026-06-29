#ifndef STRING_SPLIT_H_INCLUDED
#define STRING_SPLIT_H_INCLUDED

#include <string>
#include <vector>

namespace bee {

std::vector<std::string_view> tokenizer(std::string_view in, const char* delim=nullptr, size_t fields=0, const char* blank=nullptr); // 分隔符可以为delim字符串中任意字符
std::vector<std::string_view> split(std::string_view in, const char* separator=nullptr, size_t fields=0); // 分割符为separator字符串
void replace(std::string& target, const char* search, const char* replace);

void ltrim(std::string& v, const char* blank=nullptr);
void rtrim(std::string& v, const char* blank=nullptr);
void trim(std::string& v, const char* blank=nullptr);

std::string_view ltrim(std::string_view v, const char* blank=nullptr);
std::string_view rtrim(std::string_view v, const char* blank=nullptr);
std::string_view trim(std::string_view v, const char* blank=nullptr);

} //namespace bee

#endif
