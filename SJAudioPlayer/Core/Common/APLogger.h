//
//  APLogger.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/19.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "APDefines.h"

NS_ASSUME_NONNULL_BEGIN

@interface APLogger : NSObject
+ (instancetype)shared;

/// If yes, the log will be output on the console. The default value is NO.
@property (nonatomic, getter=isEnabledConsoleLog) BOOL enabledConsoleLog;

/// The default value is APLogOptionDefault.
@property (nonatomic) APLogOptions options;

/// The default value is APLogLevelDebug.
@property (nonatomic) APLogLevel level;

- (void)option:(APLogOptions)option level:(APLogLevel)level addLog:(NSString *)format, ... NS_FORMAT_FUNCTION(3,4);
@end

#ifdef DEBUG
#define APDebugLog(__option__, format, arg...) \
    [APLogger.shared option:__option__ level:APLogLevelDebug addLog:format, ##arg]
#define APErrorLog(__option__, format, arg...) \
    [APLogger.shared option:__option__ level:APLogLevelError addLog:format, ##arg]

#define APContentDownloadLineDebugLog(format, arg...) \
    APDebugLog(APLogOptionContentDownloadLine, format, ##arg)
#define APContentDownloadLineErrorLog(format, arg...) \
    APErrorLog(APLogOptionContentDownloadLine, format, ##arg)

#define APAudioPlayerDebugLog(format, arg...) \
    APDebugLog(APLogOptionAudioPlayer, format, ##arg)
#define APAudioPlayerErrorLog(format, arg...) \
    APErrorLog(APLogOptionAudioPlayer, format, ##arg)
#else
#define APDebugLog(option, format, arg...)
#define APErrorLog(option, format, arg...)
#define APContentDownloadLineDebugLog(format, arg...)
#define APContentDownloadLineErrorLog(format, arg...)
#define APAudioPlayerDebugLog(format, arg...)
#define APAudioPlayerErrorLog(format, arg...)
#endif
NS_ASSUME_NONNULL_END
