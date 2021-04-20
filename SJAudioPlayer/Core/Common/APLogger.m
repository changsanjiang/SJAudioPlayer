//
//  APLogger.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/19.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APLogger.h"
#import <stdarg.h>

@implementation APLogger
+ (instancetype)shared {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if ( self ) {
        _options = APLogOptionDefault;
    }
    return self;
}

- (void)option:(APLogOptions)option level:(APLogLevel)level addLog:(NSString *)format, ... NS_FORMAT_FUNCTION(3,4) {
    if ( format == nil ) return;
    if ( level < _level ) return;
    
    if ( _enabledConsoleLog && (option & _options) ) {
        va_list ap;
        va_start(ap, format);
        NSString *string = [NSString.alloc initWithFormat:format arguments:ap];
        va_end(ap);
        
        printf("%s", string.UTF8String);
    }
}
@end
