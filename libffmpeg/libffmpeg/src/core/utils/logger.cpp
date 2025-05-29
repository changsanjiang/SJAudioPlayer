//
// Created on 2025/5/29.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "logger.h"
#include "str_utils.h"
#include <stdio.h>

#if defined (FFAV_PLATFORM_OHOS)
    #undef LOG_TAG
    #define LOG_TAG "FFAV_LOG"  
    #include "hilog/log.h"
#endif

/// 打印消息到控制台
extern "C" void _ff_console_print_msg(const char *msg) {
#if defined (FFAV_PLATFORM_OHOS)
    OH_LOG_INFO(LOG_APP, msg, NULL);
#elif defined (FFAV_PLATFORM_IOS)
    printf(msg);
#endif
}

/// 打印消息到控制台
extern "C" void ff_console_print(const char *format, ...) {
    va_list args;
    va_start(args, format);
    ff_console_vprint(format, args); 
    va_end(args);
}

/// 打印消息到控制台
extern "C" void ff_console_vprint(const char *fmt, va_list args) {
    char *message = ff_cstr_create(fmt, args);
    if ( message ) {
        _ff_console_print_msg(message);
        ff_cstr_free(&message);
    }
}
