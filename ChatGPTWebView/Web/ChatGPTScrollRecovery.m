#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static const void *CPChatGPTScrollScriptInstalledKey = &CPChatGPTScrollScriptInstalledKey;

@interface WKWebView (ContextPortChatGPTScrollRecovery)
- (void)cp_scrollRecovery_didMoveToWindow;
@end

@implementation WKWebView (ContextPortChatGPTScrollRecovery)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMove = class_getInstanceMethod(self, @selector(didMoveToWindow));
        Method replacementMove = class_getInstanceMethod(self, @selector(cp_scrollRecovery_didMoveToWindow));
        method_exchangeImplementations(originalMove, replacementMove);
    });
}

- (void)cp_scrollRecovery_didMoveToWindow {
    [self cp_scrollRecovery_didMoveToWindow];
    [self cp_installChatGPTScrollRecoveryScriptIfNeeded];
    [self cp_scheduleChatGPTScrollRecovery];
}

- (BOOL)cp_isChatGPTScrollRecoveryURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (host.length == 0) return NO;
    return [host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"];
}

- (void)cp_prepareNativeScrollViewForChatGPT {
    UIScrollView *scrollView = self.scrollView;
    scrollView.scrollEnabled = YES;
    scrollView.userInteractionEnabled = YES;
    scrollView.directionalLockEnabled = YES;
    scrollView.panGestureRecognizer.enabled = YES;
    scrollView.delaysContentTouches = NO;

    // ChatGPT normally scrolls inside its own DOM container. Keep the outer
    // WKWebView stable while leaving vertical interaction enabled.
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
}

- (void)cp_installChatGPTScrollRecoveryScriptIfNeeded {
    if ([objc_getAssociatedObject(self, CPChatGPTScrollScriptInstalledKey) boolValue]) return;

    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:[self cp_chatGPTScrollRecoveryScript]
        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
        forMainFrameOnly:YES];
    [self.configuration.userContentController addUserScript:script];
    objc_setAssociatedObject(self, CPChatGPTScrollScriptInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)cp_scheduleChatGPTScrollRecovery {
    [self cp_prepareNativeScrollViewForChatGPT];

    __weak WKWebView *weakWebView = self;
    NSArray<NSNumber *> *delays = @[@0.25, @0.75, @1.5, @3.0, @5.0, @8.0, @12.0];
    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *webView = weakWebView;
                if (!webView || ![webView cp_isChatGPTScrollRecoveryURL:webView.URL]) return;
                [webView cp_prepareNativeScrollViewForChatGPT];
                [webView evaluateJavaScript:[webView cp_chatGPTScrollRecoveryScript]
                          completionHandler:nil];
            }
        );
    }
}

- (NSString *)cp_chatGPTScrollRecoveryScript {
    return @"(() => {"
        "try {"
          "if (!/(^|\\.)chatgpt\\.com$/.test(location.hostname)) return false;"
          "const manager = window.__contextPortChatPerformance;"
          "if (manager && manager.providerID === 'chatgpt' && typeof manager.destroy === 'function') manager.destroy();"
          "document.getElementById('contextport-chat-performance-style')?.remove();"
          "document.querySelectorAll('.contextport-performance-hidden').forEach(element => {"
            "element.classList.remove('contextport-performance-hidden');"
            "element.removeAttribute('aria-hidden');"
            "element.removeAttribute('data-contextport-performance-message');"
          "});"

          "const stateKey = '__contextPortChatScrollRecoveryState';"
          "const currentURL = location.href;"
          "const previous = window[stateKey];"
          "if (previous && previous.url !== currentURL && typeof previous.destroy === 'function') previous.destroy();"
          "const state = window[stateKey] && window[stateKey].url === currentURL"
            "? window[stateKey]"
            ": {url: currentURL, followLatest: true, bottomEstablished: false, observer: null, timer: null, scrollTarget: null, scrollListener: null, lastTop: 0, programmaticUntil: 0, destroy: null};"
          "window[stateKey] = state;"

          "const turnSelector = '[data-message-author-role], section[data-testid^=conversation-turn-], [data-testid*=conversation-turn]';"
          "const distanceFromBottom = element => Math.max(0, element.scrollHeight - element.clientHeight - element.scrollTop);"
          "const isVisible = element => {"
            "const rect = element.getBoundingClientRect();"
            "return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < window.innerHeight;"
          "};"
          "const candidates = () => {"
            "const items = [document.scrollingElement, document.documentElement, document.body, ...document.querySelectorAll('main, [role=main], [data-scroll-root], [class*=overflow-y-auto], [class*=overflow-y-scroll], [style*=overflow-y]')];"
            "return Array.from(new Set(items.filter(Boolean)));"
          "};"
          "const findBest = () => {"
            "let best = null;"
            "let bestScore = -1;"
            "for (const element of candidates()) {"
              "if (!(element instanceof HTMLElement)) continue;"
              "const range = Math.max(0, element.scrollHeight - element.clientHeight);"
              "if (range < 40 || element.clientHeight < 160 || !isVisible(element)) continue;"
              "const containsConversation = Boolean(element.querySelector(turnSelector));"
              "const inMain = element.matches('main, [role=main]') || Boolean(element.closest('main, [role=main]'));"
              "const score = range + element.clientHeight * 4 + (containsConversation ? 10000000 : 0) + (inMain ? 1000000 : 0);"
              "if (score > bestScore) { best = element; bestScore = score; }"
            "}"
            "return best;"
          "};"

          "const attachScrollListener = element => {"
            "if (state.scrollTarget === element) return;"
            "if (state.scrollTarget && state.scrollListener) state.scrollTarget.removeEventListener('scroll', state.scrollListener);"
            "state.scrollTarget = element;"
            "state.lastTop = element.scrollTop;"
            "state.scrollListener = () => {"
              "const top = element.scrollTop;"
              "const distance = distanceFromBottom(element);"
              "if (Date.now() < state.programmaticUntil) { state.lastTop = top; return; }"
              "if (distance <= 80) state.followLatest = true;"
              "else if (top < state.lastTop - 4) state.followLatest = false;"
              "state.lastTop = top;"
            "};"
            "element.addEventListener('scroll', state.scrollListener, {passive:true});"
          "};"

          "const pinToBottom = element => {"
            "state.programmaticUntil = Date.now() + 300;"
            "element.scrollLeft = 0;"
            "element.scrollTop = element.scrollHeight;"
            "requestAnimationFrame(() => {"
              "if (!state.followLatest || state.scrollTarget !== element) return;"
              "state.programmaticUntil = Date.now() + 200;"
              "element.scrollTop = element.scrollHeight;"
              "state.lastTop = element.scrollTop;"
            "});"
            "state.bottomEstablished = true;"
          "};"

          "const repair = forceFollow => {"
            "const best = findBest();"
            "if (!best) return false;"
            "attachScrollListener(best);"
            "best.style.setProperty('overflow-y', 'auto', 'important');"
            "best.style.setProperty('overflow-x', 'hidden', 'important');"
            "best.style.setProperty('-webkit-overflow-scrolling', 'touch', 'important');"
            "best.style.setProperty('touch-action', 'pan-y', 'important');"
            "best.style.setProperty('overscroll-behavior-y', 'contain', 'important');"
            "best.style.setProperty('overscroll-behavior-x', 'none', 'important');"
            "document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');"
            "document.documentElement.style.setProperty('overscroll-behavior-x', 'none', 'important');"
            "document.body?.style.setProperty('overflow-x', 'hidden', 'important');"
            "document.body?.style.setProperty('overscroll-behavior-x', 'none', 'important');"
            "if (forceFollow) state.followLatest = true;"
            "const hasConversation = Boolean(document.querySelector(turnSelector));"
            "if (hasConversation && state.followLatest) pinToBottom(best);"
            "return true;"
          "};"

          "state.destroy = () => {"
            "state.observer?.disconnect();"
            "state.observer = null;"
            "if (state.timer) clearTimeout(state.timer);"
            "state.timer = null;"
            "if (state.scrollTarget && state.scrollListener) state.scrollTarget.removeEventListener('scroll', state.scrollListener);"
            "state.scrollTarget = null;"
            "state.scrollListener = null;"
          "};"

          "window.__contextPortScrollToBottom = () => repair(true);"
          "window.__contextPortIsFollowingLatest = () => Boolean(state.followLatest);"

          "repair(false);"
          "if (!state.observer) {"
            "state.observer = new MutationObserver(() => {"
              "if (!state.followLatest || state.timer) return;"
              "state.timer = setTimeout(() => { state.timer = null; repair(false); }, 80);"
            "});"
            "state.observer.observe(document.documentElement, {childList:true, characterData:true, subtree:true});"
          "}"
          "return true;"
        "} catch (_) { return false; }"
      "})()";
}

@end
