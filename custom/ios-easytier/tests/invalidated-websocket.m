#import <Foundation/Foundation.h>
@interface ProbeDelegate : NSObject <NSURLSessionDelegate>
@property dispatch_semaphore_t invalidated;
@end
@implementation ProbeDelegate
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
  dispatch_semaphore_signal(self.invalidated);
}
@end
int main(void) {
  @autoreleasepool {
    ProbeDelegate *delegate = [ProbeDelegate new];
    delegate.invalidated = dispatch_semaphore_create(0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:delegate delegateQueue:nil];
    NSURL *url = [NSURL URLWithString:@"ws://127.0.0.1:9/socket"];
    @try {
      NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:url];
      if (!task) return 2;
      [task cancel];
    } @catch (NSException *e) {
      fprintf(stderr, "Live session unexpectedly rejected task: %s\n", e.name.UTF8String);
      return 3;
    }
    [session invalidateAndCancel];
    if (dispatch_semaphore_wait(delegate.invalidated, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
      fprintf(stderr, "Invalidation callback timed out\n");
      return 5;
    }
    @try {
      (void)[session webSocketTaskWithURL:url];
      fprintf(stderr, "No exception after invalidation callback\n");
      return 4;
    } @catch (NSException *e) {
      fprintf(stderr, "Invalidated session exception: %s: %s\n", e.name.UTF8String, e.reason.UTF8String);
      return 0;
    }
  }
}
