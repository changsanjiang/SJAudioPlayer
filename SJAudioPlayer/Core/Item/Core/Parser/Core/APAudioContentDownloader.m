//
//  APAudioContentDownloader.m
//  AudioCore
//
//  Created by BD on 2021/3/14.
//

#import "APAudioContentDownloader.h"

static dispatch_queue_t ap_queue;

@interface APAudioContentDownloader () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSOperationQueue *sessionDelegateQueue;
@property (nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *errorDictionary;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<APAudioContentDownloaderTaskDelegate>> *delegateDictionary;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@end

@implementation APAudioContentDownloader

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ap_queue = dispatch_queue_create("queue.APAudioContentDownloader", DISPATCH_QUEUE_CONCURRENT);
    });
}

+ (instancetype)shared {
    static APAudioContentDownloader *obj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        obj = [[self alloc] init];
    });
    return obj;
}

- (instancetype)init {
    if (self = [super init]) {
        _timeoutInterval = 30.0f;
        _backgroundTask = UIBackgroundTaskInvalid;
        _errorDictionary = [NSMutableDictionary dictionary];
        _delegateDictionary = [NSMutableDictionary dictionary];
        _sessionDelegateQueue = [[NSOperationQueue alloc] init];
        _sessionDelegateQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        _sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _sessionConfiguration.timeoutIntervalForRequest = _timeoutInterval;
        _sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringCacheData;
        _session = [NSURLSession sessionWithConfiguration:_sessionConfiguration delegate:self delegateQueue:_sessionDelegateQueue];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:[UIApplication sharedApplication]];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
 
- (nullable NSURLSessionTask *)downloadWithRequest:(NSURLRequest *)requestParam priority:(float)priority delegate:(id<APAudioContentDownloaderTaskDelegate>)delegate {
    NSURLRequest *request = [self _requestWithParam:requestParam];
    if ( request == nil )
        return nil;
    
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
    task.priority = priority;
    dispatch_barrier_sync(ap_queue, ^{
        _taskCount += 1;
    });
    [self _setDelegate:delegate forTask:task];
    [task resume];
     
    return task;
}

- (void)cancelAllDownloadTasks {
    dispatch_barrier_sync(ap_queue, ^{
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [_session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
            [dataTasks makeObjectsPerformSelector:@selector(cancel)];
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        _taskCount = 0;
    });
}
 
@synthesize taskCount = _taskCount;
- (NSInteger)taskCount {
    __block NSInteger taskCount = 0;
    dispatch_barrier_sync(ap_queue, ^{
        taskCount = _taskCount;
    });
    return taskCount;
}

#pragma mark - mark

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(request);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(__kindof NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    id<APAudioContentDownloaderTaskDelegate> delegate = [self _delegateForTask:task];
    if ( delegate != nil ) {
        [delegate downloadTask:task didReceiveResponse:response];
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)dataParam {
     __auto_type delegate = [self _delegateForTask:dataTask];
    [delegate downloadTask:dataTask didReceiveData:dataParam];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)errorParam {
    dispatch_barrier_sync(ap_queue, ^{
        if ( _taskCount > 0 ) _taskCount -= 1;
    });
    NSError *error = [self _errorForTask:task] ?: errorParam;
    
    __auto_type delegate = [self _delegateForTask:task];
    [delegate downloadTask:task didCompleteWithError:error];
    
    [self _setDelegate:nil forTask:task];
    [self _setError:nil forTask:task];
}

#pragma mark -

- (NSURLRequest *)_requestWithParam:(NSURLRequest *)param {
    NSMutableURLRequest *request = [param mutableCopy];
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    request.timeoutInterval = _timeoutInterval;
    return request;
}

#pragma mark - Background Task

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    [self _beginBackgroundTaskIfNeeded];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    [self _endBackgroundTaskIfNeeded];
}

- (void)_endBackgroundTaskDelay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _endBackgroundTaskIfNeeded];
    });
}

- (void)_beginBackgroundTaskIfNeeded {
    dispatch_barrier_sync(ap_queue, ^{
        if ( _delegateDictionary.count != 0 && self->_backgroundTask == UIBackgroundTaskInvalid ) {
            self->_backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                [self _endBackgroundTaskIfNeeded];
            }];
        }
    });
}

- (void)_endBackgroundTaskIfNeeded {
    dispatch_barrier_sync(ap_queue, ^{
        if ( _delegateDictionary.count == 0 && self->_backgroundTask != UIBackgroundTaskInvalid ) {
            [UIApplication.sharedApplication endBackgroundTask:_backgroundTask];
            _backgroundTask = UIBackgroundTaskInvalid;
        }
    });
}

#pragma mark -

- (void)_setDelegate:(nullable id<APAudioContentDownloaderTaskDelegate>)delegate forTask:(NSURLSessionTask *)task {
    dispatch_barrier_sync(ap_queue, ^{
        self->_delegateDictionary[@(task.taskIdentifier)] = delegate;
        if ( delegate == nil && self->_delegateDictionary.count == 0 ) {
            [self _endBackgroundTaskDelay];
        }
    });
}

- (nullable id<APAudioContentDownloaderTaskDelegate>)_delegateForTask:(NSURLSessionTask *)task {
    __block id<APAudioContentDownloaderTaskDelegate> delegate = nil;
    dispatch_sync(ap_queue, ^{
        delegate = self->_delegateDictionary[@(task.taskIdentifier)];
    });
    return delegate;
}

- (void)_setError:(nullable NSError *)error forTask:(NSURLSessionTask *)task {
    dispatch_barrier_sync(ap_queue, ^{
        self->_errorDictionary[@(task.taskIdentifier)] = error;
    });
}

- (nullable NSError *)_errorForTask:(NSURLSessionTask *)task {
    __block NSError *error;
    dispatch_sync(ap_queue, ^{
        error = self->_errorDictionary[@(task.taskIdentifier)];
    });
    return error;
}
@end
