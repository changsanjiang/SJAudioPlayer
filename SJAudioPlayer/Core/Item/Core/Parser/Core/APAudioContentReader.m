//
//  APAudioContentReader.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioContentReader.h"
#include <CommonCrypto/CommonCrypto.h>
#import "APError.h"
#import "APLogger.h"

#define APBytes_ThrottleValue (8192)


typedef NS_ENUM(NSUInteger, APAudioContentReaderStatus) {
    APAudioContentReaderStatusSuspend = 1 << 0,
    APAudioContentReaderStatusRunning = 1 << 1,
    APAudioContentReaderStatusError   = 1 << 2 | APAudioContentReaderStatusSuspend,
    APAudioContentReaderStatusStopped = 1 << 3 | APAudioContentReaderStatusSuspend,
};

@interface APAudioContentFileReader : APAudioContentReader

@end
 
@interface APAudioContentHTTPReader : APAudioContentReader

@end

@interface APAudioContentReader () {
    @protected
    APAudioContentReaderStatus _status;
    NSURL *_URL;
    id<APAudioOptions> _options;
    __weak id<APAudioContentReaderDelegate> _delegate;
    dispatch_queue_t _queue;
    UInt64 _offset;
    BOOL _isPrepared;
    UInt64 _countOfBytesTotalLength;
}
@end
 
@implementation APAudioContentReader

+ (instancetype)contentReaderWithURL:(NSURL *)URL  options:(nullable id<APAudioOptions>)options delegate:(id<APAudioContentReaderDelegate>)delegate queue:(dispatch_queue_t)queue {
    return URL.isFileURL ?
                [APAudioContentFileReader.alloc initWithURL:URL options:options delegate:delegate queue:queue] :
                [APAudioContentHTTPReader.alloc initWithURL:URL options:options delegate:delegate queue:queue];
}

- (instancetype)initWithURL:(NSURL *)URL options:(nullable id<APAudioOptions>)options delegate:(id<APAudioContentReaderDelegate>)delegate queue:(dispatch_queue_t)queue {
    self = [super init];
    if ( self ) {
        _status = APAudioContentReaderStatusSuspend;
        _URL = URL;
        _options = options;
        _delegate = delegate;
        _queue = queue;
    }
    return self;
}

- (UInt64)countOfBytesTotalLength {
    return _countOfBytesTotalLength;
}

- (UInt64)offset {
    return _offset;
}

- (float)contentLoadProgress { return 0; }
- (void)prepare { }
- (void)seekToOffset:(UInt64)offsetInBytes { }
- (void)retry { }
- (void)resume { }
- (void)suspend { }
- (void)stop { }
@end

@implementation APAudioContentFileReader {
    dispatch_source_t _sourceForRead;
    int _file;
    void *_buffer;
}

- (void)dealloc {
    if ( _sourceForRead != nil ) {
        dispatch_source_cancel(_sourceForRead);
        // Cancelling a dispatch source doesn't invoke the cancel handler if the dispatch source is paused.
        if ( _status & APAudioContentReaderStatusSuspend )
            dispatch_resume(_sourceForRead);
    }
    if ( _buffer != NULL )
        free(_buffer);
}

- (float)contentLoadProgress {
    return 1;
}

- (void)seekToOffset:(UInt64)offsetInBytes {
    [self _prepareIfNeeded];
    
    off_t result = lseek(_file, offsetInBytes, SEEK_SET);
    if ( result < 0 ) {
        [self _onError:[NSError ap_errorWithCode:APContentReaderErrorFileFailedToSeek userInfo:@{
            APErrorUserInfoURLKey : _URL,
            APErrorUserInfoFileTotalLengthKey : @(_countOfBytesTotalLength),
            APErrorUserInfoFileSeekOffsetKey : @(offsetInBytes),
            NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentReaderErrorFileFailedToSeek)
        }]];
        return;
    }
    
    _offset = offsetInBytes;
    
    if ( _status != APAudioContentReaderStatusRunning ) {
        _status = APAudioContentReaderStatusRunning;
        dispatch_resume(_sourceForRead);
    }
}

- (void)retry {
    [self seekToOffset:self.offset];
}

- (void)resume {
    switch ( _status ) {
        case APAudioContentReaderStatusRunning:
        case APAudioContentReaderStatusError:
            break;
        case APAudioContentReaderStatusStopped:
        case APAudioContentReaderStatusSuspend: {
            [self _prepareIfNeeded];
            _status = APAudioContentReaderStatusRunning;
            if ( _sourceForRead != nil )
                dispatch_resume(_sourceForRead);
        }
            break;
    }
}

- (void)suspend {
    switch ( _status ) {
        case APAudioContentReaderStatusStopped:
        case APAudioContentReaderStatusSuspend:
        case APAudioContentReaderStatusError:
            break;
        case APAudioContentReaderStatusRunning: {
            if ( _sourceForRead != nil && _status == APAudioContentReaderStatusRunning )
                dispatch_suspend(_sourceForRead);
            _status = APAudioContentReaderStatusSuspend;
        }
            break;
    }
}

- (void)stop {
    switch ( _status ) {
        case APAudioContentReaderStatusError:
        case APAudioContentReaderStatusStopped:
            break;
        case APAudioContentReaderStatusSuspend:
        case APAudioContentReaderStatusRunning: {
            if ( _sourceForRead != nil && _status == APAudioContentReaderStatusRunning )
                dispatch_suspend(_sourceForRead);
            _status = APAudioContentReaderStatusStopped;
        }
            break;
    }
}
 
#pragma mark - mark

- (void)_prepareIfNeeded {
    if ( _isPrepared )
        return;
    _isPrepared = YES;
    
    _countOfBytesTotalLength = (UInt64)[NSFileManager.defaultManager attributesOfItemAtPath:_URL.path error:NULL].fileSize;
    
    // man 2 open
    _file = open(_URL.path.UTF8String, (O_RDONLY | O_NONBLOCK));
    if ( _file < 0 ) {
        [self _onError:[NSError ap_errorWithCode:APContentReaderErrorCouldNotOpenFile userInfo:@{
            APErrorUserInfoURLKey : _URL,
            NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentReaderErrorCouldNotOpenFile)
        }]];
        return;
    }
    
    _sourceForRead = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _file, 0, _queue);
    __weak typeof(self) _self = self;
    dispatch_source_set_event_handler(_sourceForRead, ^{
        __strong typeof(_self) self = _self;
        if ( self == nil ) return;
        [self _pullNextBuffer];
    });
    
    int file = _file;
    dispatch_source_set_cancel_handler(_sourceForRead, ^{
        close(file);
    });
}

- (void)_pullNextBuffer {
    BOOL isOK = NO;
    size_t capacity = dispatch_source_get_data(_sourceForRead);
    if ( capacity > APBytes_ThrottleValue )
        capacity = APBytes_ThrottleValue;
    if ( _buffer == NULL )
        _buffer = malloc(APBytes_ThrottleValue);

    if ( _buffer != NULL ) {
        // man 2 read
        ssize_t length = read(_file, _buffer, capacity);

        if ( length > 0 ) {
            UInt64 offset = _offset;
            _offset += length;
            NSData *data = [NSData.alloc initWithBytes:_buffer length:length];
            if ( _options.dataReadDecoder != nil ) {
                data = _options.dataReadDecoder(data, offset);
            }
            // eof
            BOOL isEOF = _offset == _countOfBytesTotalLength;
            if ( isEOF ) {
                [self suspend];
            }
            [_delegate contentReader:self hasNewAvailableData:data atOffset:offset];
        }
        isOK = YES;
    }
    
    if ( !isOK ) {
        [self _onError:[NSError ap_errorWithCode:APContentReaderErrorFileFailedToReadData userInfo:@{
            APErrorUserInfoURLKey : _URL,
            NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentReaderErrorFileFailedToReadData)
        }]];
    }
}

- (void)_onError:(NSError *)error {
    if ( _status == APAudioContentReaderStatusRunning ) {
        dispatch_suspend(_sourceForRead);
    }
    _status = APAudioContentReaderStatusError;
    
    [_delegate contentReader:self anErrorOccurred:error];
}
@end


#pragma mark - APAudioContentHTTPReader

#import "APAudioContentDownloader.h"

@interface APAudioContentFile : NSObject
- (instancetype)initWithFilepath:(NSString *)filepath atOffset:(UInt64)offset;
@property (nonatomic, readonly) UInt64 offset;
@property (nonatomic, readonly) UInt64 length;
@property (nonatomic, weak, nullable) APAudioContentFile *next;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;
- (nullable NSData *)readDataAtOffset:(UInt64)offset capacity:(UInt64)capacity error:(NSError **)error;
- (void)close;
@end

@implementation APAudioContentFile {
    NSFileHandle *_writer;
    NSFileHandle *_reader;
    NSString *_filepath;
}

- (instancetype)initWithFilepath:(NSString *)filepath atOffset:(UInt64)offset {
    self = [super init];
    if ( self ) {
        _filepath = filepath.copy;
        _offset = offset;
    }
    return self;
}

- (void)close {
    @try {
        if ( _writer != nil ) {
            [_writer synchronizeFile];
            [_writer closeFile];
        }
        if ( _reader != nil )
            [_reader closeFile];
    } @catch (__unused NSException *exception) {
        
    }
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error {
    if ( _writer == nil ) {
        @try {
            _writer = [NSFileHandle fileHandleForWritingAtPath:_filepath];
        } @catch (NSException *exception) {
            if ( error != NULL ) {
                *error = [NSError ap_errorWithCode:APUnknownError userInfo:@{
                    APErrorUserInfoExceptionKey : exception
                }];
            }
        }
    }

    if ( _writer == nil )
        return NO;
    
    @try {
        [_writer writeData:data];
        _length += data.length;
        return YES;
    } @catch (NSException *exception) {
        if ( error != NULL ) {
            *error = [NSError ap_errorWithCode:APUnknownError userInfo:@{
                APErrorUserInfoExceptionKey : exception
            }];
        }
    }
    return NO;
}

- (nullable NSData *)readDataAtOffset:(UInt64)offset capacity:(UInt64)capacity error:(NSError **)error {
    if ( _reader == nil ) {
        @try {
            _reader = [NSFileHandle fileHandleForReadingAtPath:_filepath];
        } @catch (NSException *exception) {
            if ( error != NULL ) {
                *error = [NSError ap_errorWithCode:APUnknownError userInfo:@{
                    APErrorUserInfoExceptionKey : exception
                }];
            }
            return nil;
        }
    }
    
    @try {
        [_reader seekToFileOffset:offset - _offset];
    } @catch (NSException *exception) {
        if ( error != NULL ) {
            *error = [NSError ap_errorWithCode:APUnknownError userInfo:@{
                APErrorUserInfoExceptionKey : exception
            }];
        }
        return nil;
    }
    
    UInt64 length = capacity;
    UInt64 max = _offset + _length;
    if ( (offset + length) > max ) {
        length = max - offset;
    }
    
    if ( length == 0 )
        return NSData.data;
    
    @try {
        NSData *data = [_reader readDataOfLength:(NSUInteger)length];
        return data;
    } @catch (NSException *exception) {
        if ( error != NULL ) {
            *error = [NSError ap_errorWithCode:APUnknownError userInfo:@{
                APErrorUserInfoExceptionKey : exception
            }];
        }
        return nil;
    }
}


- (NSString *)description {
    return [NSString stringWithFormat:@"%@: <%p> { offset: %llu, length: %llu }", NSStringFromClass(self.class), self, _offset, _length];
}
@end

@interface APAudioContentFileProvider : NSObject
+ (instancetype)fileProviderWithURL:(NSURL *)URL;
@property (nonatomic, copy, readonly, nullable) NSArray<APAudioContentFile *> *files;
- (nullable APAudioContentFile *)createFileAtOffset:(UInt64)offset error:(NSError **)error;
@end

@implementation APAudioContentFileProvider {
    NSURL *_URL;
    NSString *_directory;
    NSMutableArray<APAudioContentFile *> *_files;
}
static dispatch_semaphore_t ap_semaphore;
+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ap_semaphore = dispatch_semaphore_create(1);
    });
}

+ (instancetype)fileProviderWithURL:(NSURL *)URL {
    APAudioContentFileProvider *provider = APAudioContentFileProvider.alloc.init;
    provider->_URL = URL;
    return provider;
}

- (void)dealloc {
    if ( _directory != nil ) {
        dispatch_semaphore_wait(ap_semaphore, DISPATCH_TIME_FOREVER);
        [_files makeObjectsPerformSelector:@selector(close)];
        [NSFileManager.defaultManager removeItemAtPath:_directory error:NULL];
        dispatch_semaphore_signal(ap_semaphore);
    }
}
 
- (nullable NSArray<APAudioContentFile *> *)files {
    return _files.copy;
}

static inline NSString *
AP_MD5(NSString *str) {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]];
}

- (nullable APAudioContentFile *)createFileAtOffset:(UInt64)offset error:(NSError **)error {
    if ( _directory == nil ) {
        NSString *foldername = AP_MD5(_URL.absoluteString);
        int index = 0;
        dispatch_semaphore_wait(ap_semaphore, DISPATCH_TIME_FOREVER);
        while ( true ) {
            NSString *path = [NSString stringWithFormat:@"com.APAudioPlaybackController.cache/%@/%d", foldername, index];
            NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:path];
            if ( [NSFileManager.defaultManager fileExistsAtPath:directory] ) {
                index += 1;
                continue;
            }
            if ( ![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error] ) {
                return nil;
            }
            _directory = directory;
            break;
        }
        dispatch_semaphore_signal(ap_semaphore);
    }
    
    NSString *filename = [self _filenameWithOffset:offset];
    NSString *filepath = [self _filePathForFilename:filename];
    [NSFileManager.defaultManager createFileAtPath:filepath contents:nil attributes:nil];
    APAudioContentFile *file = [APAudioContentFile.alloc initWithFilepath:filepath atOffset:offset];
    if ( _files == nil )
        _files = NSMutableArray.array;
    [_files addObject:file];
    return file;
}

- (nullable NSString *)_filePathForFilename:(NSString *)filename {
    return [filename hasPrefix:@"ap_"] ? [_directory stringByAppendingPathComponent:filename] : nil;
}

- (NSString *)_filenameWithOffset:(UInt64)offset {
    return [NSString stringWithFormat:@"ap_%llu", offset];
}

@end

@protocol APAudioContentDownloadLineDelegate;

@interface APAudioContentDownloadLine : NSObject<APAudioContentDownloaderTaskDelegate>
- (instancetype)initWithURL:(NSURL *)URL HTTPAdditionalHeaders:(NSDictionary *)HTTPAdditionalHeaders queue:(dispatch_queue_t)queue delegate:(id<APAudioContentDownloadLineDelegate>)delegate;
@property (nonatomic, weak, readonly, nullable) id<APAudioContentDownloadLineDelegate> delegate;
@property (nonatomic, readonly) UInt64 countOfBytesTotalLength;
@property (nonatomic, readonly) UInt64 offset;
@property (nonatomic, readonly) float contentLoadProgress;
- (void)seekToOffset:(UInt64)offset;
- (void)stop;
@end

@protocol APAudioContentDownloadLineDelegate <NSObject>
- (void)downloadLine:(APAudioContentDownloadLine *)downloadLine didFinishSeekWithFile:(APAudioContentFile *)file;
- (void)downloadLine:(APAudioContentDownloadLine *)downloadLine didWriteDataWithFile:(APAudioContentFile *)file;
- (void)downloadLine:(APAudioContentDownloadLine *)downloadLine anErrorOccurred:(NSError *)error;
@end


@implementation APAudioContentDownloadLine {
    NSURL *_URL;
    dispatch_queue_t _queue;
    APAudioContentFileProvider *_Nullable _provider;
    NSURLSessionTask *_Nullable _task;
    APAudioContentFile *_Nullable _head;
    NSMutableDictionary<NSNumber *, APAudioContentFile *> *_taskFiles;
    NSDictionary *_Nullable _HTTPAdditionalHeaders;
}

static dispatch_semaphore_t ap_semaphore;
+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ap_semaphore = dispatch_semaphore_create(1);
    });
}

- (instancetype)initWithURL:(NSURL *)URL HTTPAdditionalHeaders:(NSDictionary *)HTTPAdditionalHeaders queue:(dispatch_queue_t)queue delegate:(id<APAudioContentDownloadLineDelegate>)delegate {
    self = [super init];
    if ( self ) {
        _URL = URL;
        _HTTPAdditionalHeaders = HTTPAdditionalHeaders;
        _queue = queue;
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc {
    [self _cancelCurrentTask];
}

- (float)contentLoadProgress {
    if ( _countOfBytesTotalLength == 0 )
        return 0.0f;
    
    // 获取offset后, 连续文件的进度
    
    UInt64 count = _offset;
    APAudioContentFile *cur = _head;
    while ( cur != nil ) {
        UInt64 position = cur.offset + cur.length;
        if ( position >= _offset ) {
            count = position;
    
            // 不连续则退出
            if ( cur.next.offset != position ) {
                break;
            }
        }
        cur = cur.next;
    }
    return (double)(count) / (double)(_countOfBytesTotalLength);
}

- (void)seekToOffset:(UInt64)offset {
    _offset = offset;
    APContentDownloadLineDebugLog(@"%@: <%p>.%s { offset: %llu }\n", NSStringFromClass(self.class), self, sel_getName(_cmd), offset);
    
    [self _cancelCurrentTask];
    // 遍历所有file, 查询是否有 offset 相交的file
    APAudioContentFile *cur = _head;
    // 距离offset最近的file(前面的)
    APAudioContentFile *pre = nil;
    while ( cur != nil ) {
        NSRange range = NSMakeRange((NSUInteger)cur.offset, (NSUInteger)cur.length);
        if ( cur.offset == offset )
            break;
        if ( NSLocationInRange((NSUInteger)offset, range) )
            break;
        if ( cur.offset <= offset )
            pre = cur;
        cur = cur.next;
    }
    
    // 没有相交的则创建
    if ( cur == nil ) {
        if ( _provider == nil )
            _provider = [APAudioContentFileProvider fileProviderWithURL:_URL];
        
        NSError *error = nil;
        cur = [_provider createFileAtOffset:offset error:&error];
        if ( error != nil ) {
            [self _onError:error];
            return;
        }
        
        if ( _head == nil )
            _head = cur;
        else if ( pre != nil ) {
            // pre cur next
            APAudioContentFile *next = pre.next;
            pre.next = cur;
            cur.next = next;
        }
    }
    
    APContentDownloadLineDebugLog(@"%@: <%p>.didFinishSeek { cur: %@ }\n", NSStringFromClass(self.class), self, cur);

    [self _resetTask:cur];
    [_delegate downloadLine:self didFinishSeekWithFile:cur];
}

- (void)stop {
    [self _cancelCurrentTask];
}

// 从参数指定的file开始, 获取未下载部分重置下载任务
- (void)_resetTask:(APAudioContentFile *)file {
//
//    NSRange range1 = NSMakeRange(0, 2);
//    NSRange range2 = NSMakeRange(2, 4);
//    0, 1,    2, 3, 4, 5
//    maxRange1 == range2.location
//
    APAudioContentFile *cur = file;
    // bytes=start-end
    //  or
    // bytes=start-
    NSNumber *start = nil;
    NSNumber *end = nil;
    // 获取未下载部分
    while ( cur.next != nil ) {
        APAudioContentFile *next = cur.next;
        if ( cur.offset + cur.length != next.offset ) {
            start = @(cur.offset + cur.length);
            end = @(next.offset - 1);
            break;
        }
        cur = next;
    }
    
    BOOL isDownloadFinished = _countOfBytesTotalLength != 0 && ((cur.offset + cur.length) == _countOfBytesTotalLength);
    if ( isDownloadFinished )
        return;

    if ( start == nil ) {
        start = @(cur.offset + cur.length);
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest.alloc initWithURL:_URL];
    [_HTTPAdditionalHeaders enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [request setValue:obj forHTTPHeaderField:key];
    }];
    [request setValue:[NSString stringWithFormat:@"bytes=%@-%@", start, end ?: @""] forHTTPHeaderField:@"Range"];
    _task = [APAudioContentDownloader.shared downloadWithRequest:request priority:1 delegate:self];
    if ( _taskFiles == nil )
        _taskFiles = NSMutableDictionary.dictionary;
    _taskFiles[@(_task.taskIdentifier)] = cur;
    
    APContentDownloadLineDebugLog(@"%@: <%p>.didResetTask { start: %@, end: %@ }\n", NSStringFromClass(self.class), self, start, end);
}

- (void)_onError:(NSError *)error {
    [_delegate downloadLine:self anErrorOccurred:error];
}

- (void)_cancelCurrentTask {
    if ( _task != nil && _task.state == NSURLSessionTaskStateRunning )
        [_task cancel];
    _task = nil;
}

#pragma mark - APAudioContentDownloaderTaskDelegate

- (void)downloadTask:(NSURLSessionTask *)task didReceiveResponse:(NSHTTPURLResponse *)response {
    APContentDownloadLineDebugLog(@"%@: <%p>.didReceiveData { task: %lu, response: %@ }\n", NSStringFromClass(self.class), self, (unsigned long)task.taskIdentifier, response);

    dispatch_sync(_queue, ^{
        if ( _countOfBytesTotalLength == 0 ) {
            NSDictionary *responseHeaders = response.allHeaderFields;
            NSString *bytes = responseHeaders[@"Content-Range"] ?: responseHeaders[@"content-range"];
            if ( bytes.length != 0 ) {
                NSString *prefix = @"bytes ";
                NSString *rangeString = [bytes substringWithRange:NSMakeRange(prefix.length, bytes.length - prefix.length)];
                NSArray<NSString *> *components = [rangeString componentsSeparatedByString:@"-"];
                _countOfBytesTotalLength = [components.lastObject.lastPathComponent longLongValue];
            }
        }
    });
}

- (void)downloadTask:(NSURLSessionTask *)task didReceiveData:(NSData *)data {
    APContentDownloadLineDebugLog(@"%@: <%p>.didReceiveData { task: %lu, length: %lu }\n", NSStringFromClass(self.class), self, (unsigned long)task.taskIdentifier, (unsigned long)data.length);

    dispatch_sync(_queue, ^{
        NSError *error = nil;
        APAudioContentFile *file = _taskFiles[@(task.taskIdentifier)];
        if ( file != nil && ![file writeData:data error:&error] ) {
            [self _onError:error];
            return;
        }
        [_delegate downloadLine:self didWriteDataWithFile:file];
    });
}

- (void)downloadTask:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    APContentDownloadLineDebugLog(@"%@: <%p>.didCompleteWithError { task: %lu, error: %@ }\n", NSStringFromClass(self.class), self, (unsigned long)task.taskIdentifier, error);

    dispatch_sync(_queue, ^{
        APAudioContentFile *file = _taskFiles[@(task.taskIdentifier)];
        _taskFiles[@(task.taskIdentifier)] = nil;
        
        if ( error != nil ) {
            if ( error.code != NSURLErrorCancelled )
                [self _onError:error];
            return;
        }
        
        [self _resetTask:file];
    });
}

@end


@interface APAudioContentHTTPReader()<APAudioContentDownloadLineDelegate> {
    APAudioContentDownloadLine *_download;
    APAudioContentFile *_cur;
    NSError *_Nullable _errorAfterNoData;
}
@end

@implementation APAudioContentHTTPReader

- (instancetype)initWithURL:(NSURL *)URL options:(nullable id<APAudioOptions>)options delegate:(id<APAudioContentReaderDelegate>)delegate queue:(dispatch_queue_t)queue {
    self = [super initWithURL:URL options:options delegate:delegate queue:queue];
    if ( self ) {
        _download = [APAudioContentDownloadLine.alloc initWithURL:URL HTTPAdditionalHeaders:options.HTTPAdditionalHeaders queue:queue delegate:self];
        _status = APAudioContentReaderStatusSuspend;
    }
    return self;
}

- (float)contentLoadProgress {
    return _download.contentLoadProgress;
}

- (UInt64)countOfBytesTotalLength {
    return _download.countOfBytesTotalLength;
}

- (void)seekToOffset:(UInt64)offsetInBytes {
    _errorAfterNoData = nil;
    _cur = nil;
    _offset = offsetInBytes;
    _status = APAudioContentReaderStatusRunning;
    [_download seekToOffset:offsetInBytes];
    [_delegate contentReader:self contentLoadProgressDidChange:_download.contentLoadProgress];
}

- (void)retry {
    [self seekToOffset:_offset];
}

- (void)resume {
    switch ( _status ) {
        case APAudioContentReaderStatusError:
        case APAudioContentReaderStatusRunning:
            break;
        case APAudioContentReaderStatusStopped:
        case APAudioContentReaderStatusSuspend: {
            if ( _cur != nil ) {
                _status = APAudioContentReaderStatusRunning;
                [self _readDataRecursively];
            }
            else {
                [self seekToOffset:_offset];
            }
        }
            break;
    }
}

- (void)suspend {
    switch ( _status ) {
        case APAudioContentReaderStatusStopped:
        case APAudioContentReaderStatusSuspend:
        case APAudioContentReaderStatusError:
            break;
        case APAudioContentReaderStatusRunning: {
            _status = APAudioContentReaderStatusSuspend;
        }
            break;
    }
}

- (void)stop {
    if ( _status != APAudioContentReaderStatusStopped ) {
        _status = APAudioContentReaderStatusStopped;
        [_download stop];
    }
}

#pragma mark - APAudioContentDownloadLineDelegate

- (void)downloadLine:(APAudioContentDownloadLine *)downloadLine didFinishSeekWithFile:(APAudioContentFile *)file {
    _cur = file;
    [self _readDataRecursively];
}

- (void)downloadLine:(APAudioContentDownloadLine *)downloadLine didWriteDataWithFile:(APAudioContentFile *)file {
    [_delegate contentReader:self contentLoadProgressDidChange:downloadLine.contentLoadProgress];
    if ( _cur == file ) {
        [self _readDataRecursively];
    }
}

- (void)downloadLine:(APAudioContentDownloadLine *)downloadLine anErrorOccurred:(NSError *)error {
    _errorAfterNoData = error;
    [self _readDataRecursively];
}

#pragma mark - mark

- (void)_readDataRecursively {
    if ( _status != APAudioContentReaderStatusRunning )
        return;
    if ( _cur == nil )
        return;
    NSError *error = nil;
    NSUInteger capacity = APBytes_ThrottleValue;
    BOOL noData = _offset >= _cur.offset + _cur.length;
    if ( noData ) {
        APAudioContentFile *next = _cur.next;
        if ( next != nil && next.offset == (_cur.offset + _cur.length) ) {
            _cur = next;
            [self _readDataRecursively];
            return;
        }
        
        if ( _errorAfterNoData != nil ) {
            [self _onError:_errorAfterNoData];
            return;
        }
        // Wait for the next call
        return;
    }
    
    NSData *data = [_cur readDataAtOffset:_offset capacity:capacity error:&error];
    if ( error != nil ) {
        [self _onError:error];
        return;
    }
    
    UInt64 offset = _offset;
    _offset += data.length;
    
    if ( _options.dataReadDecoder != nil ) {
        data = _options.dataReadDecoder(data, offset);
    }

    if ( _offset == _download.countOfBytesTotalLength )
        [self suspend];
    
    [_delegate contentReader:self hasNewAvailableData:data atOffset:offset];
    
    [self _readDataRecursively];
}

- (void)_onError:(NSError *)error {
    _status = APAudioContentReaderStatusError;
    [_delegate contentReader:self anErrorOccurred:error];
}

@end
