//
//  APError.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APError.h"
 
NSErrorDomain const APErrorDomain = @"lib.changsanjiang.AudioPlayer.error";
NSString *const APErrorUserInfoURLKey = @"URL";
NSString *const APErrorUserInfoErrorKey = @"error";
NSString *const APErrorUserInfoAudioEngineKey = @"engine";
NSString *const APErrorUserInfoExceptionKey = @"exception";
NSString *const APErrorUserInfoFileTotalLengthKey = @"totalLength";
NSString *const APErrorUserInfoFileSeekOffsetKey = @"offset";
NSString *const APErrorUserInfoHTTPTaskKey = @"task";
NSString *const APErrorUserInfoHTTPResponseKey = @"response";
NSString *const APErrorUserInfoErrorStatusKey = @"status";
NSString *const APErrorUserInfoInputFormatKey = @"inputFormat";
NSString *const APErrorUserInfoOutputFormatKey = @"outputFormat";
NSString *const APErrorUserInfoPCMFrameCapacityKey = @"PCMFrameCapacity";

@implementation NSError(APExtended)

+ (NSError *)ap_errorWithCode:(APErrorCode)code userInfo:(NSDictionary *)userInfo {
    return [NSError errorWithDomain:APErrorDomain code:code userInfo:userInfo];
}

@end
 

NSString *
APErrorLocalizedDescriptionFromParseBytesError(OSStatus status) {
    switch ( status ) {
        case kAudioFileStreamError_UnsupportedFileType:
            return @"The file type is not supported";
        case kAudioFileStreamError_UnsupportedDataFormat:
            return @"The data format is not supported by this file type";
        case kAudioFileStreamError_UnsupportedProperty:
            return @"The property is not supported";
        case kAudioFileStreamError_BadPropertySize:
            return @"The size of the property data was not correct";
        case kAudioFileStreamError_NotOptimized:
            return @"It is not possible to produce output packets because the file's packet table or other defining";
        case kAudioFileStreamError_InvalidPacketOffset:
            return @"A packet offset was less than zero, or past the end of the file";
        case kAudioFileStreamError_InvalidFile:
            return @"The file is malformed, or otherwise not a valid instance of an audio file of its type, or is not recognized as an audio file";
        case kAudioFileStreamError_ValueUnknown:
            return @"The property value is not present in this file before the audio data";
        case kAudioFileStreamError_DataUnavailable:
            return @"The amount of data provided to the parser was insufficient to produce any result";
        case kAudioFileStreamError_IllegalOperation:
            return @"An illegal operation was attempted";
        default:
            return @"An unspecified error occurred";
    }
}

NSString *
APErrorLocalizedDescriptionFromConverterError(OSStatus status) {
    switch ( status ) {
        case kAudioConverterErr_FormatNotSupported:
            return @"Format not supported";
        case kAudioConverterErr_OperationNotSupported:
            return @"Operation not supported";
        case kAudioConverterErr_PropertyNotSupported:
            return @"Property not supported";
        case kAudioConverterErr_InvalidInputSize:
            return @"Invalid input size";
        case kAudioConverterErr_InvalidOutputSize:
            return @"Invalid output size";
        case kAudioConverterErr_BadPropertySizeError:
            return @"Bad property size error";
        case kAudioConverterErr_RequiresPacketDescriptionsError:
            return @"Requires packet descriptions";
        case kAudioConverterErr_InputSampleRateOutOfRange:
            return @"Input sample rate out of range";
        case kAudioConverterErr_OutputSampleRateOutOfRange:
            return @"Output sample rate out of range";
        case kAudioConverterErr_HardwareInUse:
            return @"Hardware is in use";
        case kAudioConverterErr_NoHardwarePermission:
            return @"No hardware permission";
        default:
            return @"An unspecified error occurred";
    }
}

NSString *
APErrorLocalizedDescription(APErrorCode code, OSStatus status) {
    switch ( code ) {
        case APUnknownError:
            return @"An unspecified error occurred!";
        case APAudioEngineErrorUnableToStartEngine:
            return @"Unable to start audio engine!";
        case APAudioEngineErrorThrowException:
            return @"Throw exception!";
        case APContentReaderErrorCouldNotOpenFile:
            return @"Could not open file for reading!";
        case APContentReaderErrorFileFailedToSeek:
            return @"Failed to seek!";
        case APContentReaderErrorFileFailedToReadData:
            return @"Failed to read data!";
        case APContentReaderErrorHTTPResponseInvalid:
            return @"Invalid HTTP response!";
        case APContentParserErrorCouldNotOpenStream:
            return @"Could not open stream for parsing!";
        case APContentParserErrorFailedToParseBytes:
            return APErrorLocalizedDescriptionFromParseBytesError(status);
        case APContentConverterErrorFailedToCreateConverter:
            return APErrorLocalizedDescriptionFromConverterError(status);
        case APContentConverterErrorFailedToCreatePCMBuffer:
            return @"Failed to create PCM buffer for reading data!";
    }
}

NSString *__attribute__((overloadable))
APErrorLocalizedDescription(APErrorCode code) {
    return APErrorLocalizedDescription(code, noErr);
}
