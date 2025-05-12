//
//  common.h
//  Pods
//
//  Created by db on 2025/4/14.
//

#ifndef EXTERN_C_START
    #ifdef __cplusplus
        #define EXTERN_C_START extern "C" {
    #else
        #define EXTERN_C_START
    #endif
#endif

#ifndef EXTERN_C_END
    #ifdef __cplusplus
        #define EXTERN_C_END }
    #else
        #define EXTERN_C_END
    #endif
#endif
