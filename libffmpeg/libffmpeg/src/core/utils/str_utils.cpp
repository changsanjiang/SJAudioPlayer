//
// Created on 2025/5/29.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "str_utils.h"
#include <cstdio>
#include <new>

extern "C" char *ff_cstr_create(const char *fmt, va_list args) {
    if (fmt == nullptr) return nullptr; // 检查 fmt 是否为空
    
    // 使用 vsnprintf 计算格式化字符串的大小
    va_list args_copy;
    va_copy(args_copy, args);  // 拷贝 va_list，以便再次使用
    int message_length = vsnprintf(nullptr, 0, fmt, args_copy);
    va_end(args_copy);  // 释放 args_copy
    
    if (message_length < 0) return NULL; // 如果计算失败则返回

    // 分配内存来存储格式化的字符串
    char *message = new (std::nothrow) char[message_length + 1];
    if (!message) return NULL;  // 检查内存分配是否成功
    
    vsnprintf(message, message_length + 1, fmt, args); // 生成格式化的字符串
    return message;
}

extern "C" void ff_cstr_free(char **str_ptr) {
    if ( str_ptr && *str_ptr ) {
        delete [] *str_ptr;
        *str_ptr = nullptr;
    }
}