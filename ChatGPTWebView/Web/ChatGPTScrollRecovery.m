#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

@interface WKWebView (ContextPortChatGPTScrollRecovery)
- (WKNavigation *)cp_scrollRecovery_loadRequest:(NSURLRequest *)request;
- (WKNavigation *)cp_scrollRecovery_reload;
- (void)cp_scrollRecovery_didMoveToWindow;
@end

@implementation WKWebView (ContextPortChatGPTScrollRecovery)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalLoad = class_getInstanceMethod(self, @selector(loadRequest:));
        Method replacementLoad = class_getInstanceMethod(self, @selector(cp_scrollRecovery_loadRequest:));
        method_exchangeImplementations(originalLoad, replacementLoad);

        Method originalReload = class_getInstanceMethod(self, @selector(reload));
        Method replacementReload = class_getInstanceMethod(self, @selector(cp_scrollRecovery_reload));
        method_exchangeImplementations(originalReload, replacementReload);

        Method originalMove = class_getInstanceMethod(self, @selector(didMoveToWindow));
        Method replacementMove = class_getInstanceMethod(self, @selector(cp_scrollRecovery_didMoveToWindow));
        method_exchangeImplementations(originalMove, replacementMove);
    });
}

- (WKNavigation *)cp_scrollRecovery_loadRequest:(NSURLRequest *)request {
    WKNavigation *navigation = [self cp_scrollRecovery_loadRequest:request];
    [self cp_scheduleChatGPTScrollRecoveryForURL:request.URL];
    return navigation;
}

- (WKNavigation *)cp_scrollRecovery_reload {
    WKNavigation *navigation = [self cp_scrollRecovery_reload];
    [self cp_scheduleChatGPTScrollRecoveryForURL:self.URL];
    return navigation;
}

- (void)cp_scrollRecovery_didMoveToWindow {
    [self cp_scrollRecovery_didMoveToWindow];
    [self cp_enableNativeScrolling];
    [self cp_scheduleChatGPTScrollRecoveryForURL:self.URL];
}

- (BOOL)cp_isChatGPTScrollRecoveryURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (host.length == 0) return NO;
    return [host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"];
}

- (void)cp_enableNativeScrolling {
    UIScrollView *scrollView = self.scrollView;
    scrollView.scrollEnabled = YES;
    scrollView.userInteractionEnabled = YES;
    scrollView.directionalLockEnabled = NO;
    scrollView.panGestureRecognizer.enabled = YES;
    scrollView.delaysContentTouches = NO;
}

- (void)cp_scheduleChatGPTScrollRecoveryForURL:(NSURL *)url {
    if (![self cp_isChatGPTScrollRecoveryURL:url]) return;

    [self cp_enableNativeScrolling];

    __weak WKWebView *weakWebView = self;
    NSArray<NSNumber *> *delays = @[@0.25, @1.0, @3.0];
    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *webView = weakWebView;
                if (!webView || ![webView cp_isChatGPTScrollRecoveryURL:webView.URL]) return;
                [webView cp_enableNativeScrolling];
                [webView evaluateJavaScript:[webView cp_chatGPTScrollRecoveryScript]
                          completionHandler:nil];
            }
        );
    }
}

- (NSString *)cp_chatGPTScrollRecoveryScript {
    return @"(() => {"
        "try {"
          "const manager = window.__contextPortChatPerformance;"
          "if (manager && manager.providerID === 'chatgpt' && typeof manager.destroy === 'function') manager.destroy();"
          "document.getElementById('contextport-chat-performance-style')?.remove();"
          "document.querySelectorAll('.contextport-performance-hidden').forEach(element => {"
            "element.classList.remove('contextport-performance-hidden');"
            "element.removeAttribute('aria-hidden');"
            "element.removeAttribute('data-contextport-performance-message');"
          "});"
          "const roots = [document.documentElement, document.body, document.querySelector('main')].filter(Boolean);"
          "roots.forEach(element => {"
            "if (element.style && element.style.overflow === 'hidden') element.style.removeProperty('overflow');"
            "if (element.style && element.style.touchAction === 'none') element.style.removeProperty('touch-action');"
          "});"
          "return true;"
        "} catch (_) { return false; }"
      "})()";
}

@end
