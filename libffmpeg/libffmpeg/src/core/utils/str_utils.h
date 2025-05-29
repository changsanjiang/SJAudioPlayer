//
// Created on 2025/5/29.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFMPEG_HARMONY_OS_STR_UTILS_H
#define FFMPEG_HARMONY_OS_STR_UTILS_H

#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

    char *ff_cstr_create(const char *fmt, va_list args); // should delete str after;
    void ff_cstr_free(char **str_ptr);

#ifdef __cplusplus
}
#endif


#endif //FFMPEG_HARMONY_OS_STR_UTILS_H
