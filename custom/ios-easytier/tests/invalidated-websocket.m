#import <Foundation/Foundation.h>
int main(void) {
  @autoreleasepool {
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
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
    @try {
      (void)[session webSocketTaskWithURL:url];
      fprintf(stderr, "No exception after invalidation\n");
      return 4;
    } @catch (NSException *e) {
      fprintf(stderr, "Invalidated session exception: %s: %s\n", e.name.UTF8String, e.reason.UTF8String);
      return 0;
    }
  }
}
