//
//  APError.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const APErrorDomain;
typedef NS_ENUM(NSUInteger, APErrorCode) {
    APUnknownError = 100000,
    
    APAudioEngineErrorUnableToStartEngine,
    APAudioEngineErrorThrowException,
    
    APContentReaderErrorCouldNotOpenFile,
    APContentReaderErrorFileFailedToSeek,
    APContentReaderErrorFileFailedToReadData,
    APContentReaderErrorHTTPResponseInvalid,
    
    APContentParserErrorCouldNotOpenStream,
    APContentParserErrorFailedToParseBytes,
    
    APContentConverterErrorUnableToCreateConverter,
    APContentConverterErrorFailedToCreatePCMBuffer,
};

FOUNDATION_EXPORT NSString *
APErrorLocalizedDescription(APErrorCode code, OSStatus status);

FOUNDATION_EXPORT NSString *__attribute__((overloadable))
APErrorLocalizedDescription(APErrorCode code);

FOUNDATION_EXTERN NSString *const APErrorDomain;
FOUNDATION_EXTERN NSString *const APErrorUserInfoURLKey;
FOUNDATION_EXTERN NSString *const APErrorUserInfoErrorKey;
FOUNDATION_EXTERN NSString *const APErrorUserInfoAudioEngineKey;
FOUNDATION_EXTERN NSString *const APErrorUserInfoExceptionKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoFileTotalLengthKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoFileSeekOffsetKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoHTTPTaskKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoHTTPResponseKey;
FOUNDATION_EXTERN NSString *const APErrorUserInfoErrorStatusKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoInputFormatKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoOutputFormatKey;
FOUNDATION_EXPORT NSString *const APErrorUserInfoPCMFrameCapacityKey;

@interface NSError(APExtended)

+ (NSError *)ap_errorWithCode:(APErrorCode)code userInfo:(NSDictionary *)userInfo;

@end
NS_ASSUME_NONNULL_END
