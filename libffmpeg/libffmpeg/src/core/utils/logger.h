//
// Created on 2025/5/29.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFMPEG_HARMONY_OS_LOGGER_H
#define FFMPEG_HARMONY_OS_LOGGER_H

#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

void ff_console_print(const char *fmt, ...);
void ff_console_vprint(const char *fmt, va_list args);

#ifdef __cplusplus
}
#endif

#endif //FFMPEG_HARMONY_OS_LOGGER_H
