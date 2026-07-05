import Foundation
import ObjectiveC.runtime
import WebKit

private enum GrokOAuthPopupAssociatedKeys {
    static var authPopup: UInt8 = 0
}

enum GrokOAuthPopupCompatibilityPatch {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        exchangeImplementations(
            in: SecureChatGPTWebViewCoordinator.self,
            original: #selector(WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)),
            replacement: #selector(SecureChatGPTWebViewCoordinator.grokCompatibility_webView(_:createWebViewWith:for:windowFeatures:))
        )

        exchangeImplementations(
            in: WKWebView.self,
            original: #selector(WKWebView.load(_:)),
            replacement: #selector(WKWebView.grokCompatibility_load(_:))
        )
    }

    static func markAuthPopup(_ webView: WKWebView) {
        objc_setAssociatedObject(
            webView,
            &GrokOAuthPopupAssociatedKeys.authPopup,
            NSNumber(value: true),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func isAuthPopup(_ webView: WKWebView) -> Bool {
        (objc_getAssociatedObject(
            webView,
            &GrokOAuthPopupAssociatedKeys.authPopup
        ) as? NSNumber)?.boolValue == true
    }

    static func isGrokAuthContext(openerURL: URL?, requestURL: URL?) -> Bool {
        let openerHost = openerURL?.host?.lowercased() ?? ""
        let requestHost = requestURL?.host?.lowercased() ?? ""

        if openerHost == "grok.com" || openerHost.hasSuffix(".grok.com") {
            return true
        }

        return requestHost == "accounts.x.ai"
            || requestHost == "x.ai"
            || requestHost.hasSuffix(".x.ai")
            || requestHost == "x.com"
            || requestHost.hasSuffix(".x.com")
            || requestHost == "accounts.google.com"
            || requestHost == "appleid.apple.com"
            || requestHost == "challenges.cloudflare.com"
    }

    private static func exchangeImplementations(
        in targetClass: AnyClass,
        original: Selector,
        replacement: Selector
    ) {
        guard let originalMethod = class_getInstanceMethod(targetClass, original),
              let replacementMethod = class_getInstanceMethod(targetClass, replacement) else {
            assertionFailure("Unable to install Grok OAuth WebKit compatibility patch")
            return
        }

        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension SecureChatGPTWebViewCoordinator {
    @objc
    fileprivate func grokCompatibility_webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if GrokOAuthPopupCompatibilityPatch.isAuthPopup(webView) {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url else {
                return nil
            }

            webView.load(URLRequest(url: url))
            return nil
        }

        let popupWebView = grokCompatibility_webView(
            webView,
            createWebViewWith: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        guard let popupWebView,
              GrokOAuthPopupCompatibilityPatch.isGrokAuthContext(
                openerURL: webView.url,
                requestURL: navigationAction.request.url
              ) else {
            return popupWebView
        }

        GrokOAuthPopupCompatibilityPatch.markAuthPopup(popupWebView)
        return popupWebView
    }
}

extension WKWebView {
    @objc
    fileprivate func grokCompatibility_load(_ request: URLRequest) -> WKNavigation? {
        if GrokOAuthPopupCompatibilityPatch.isAuthPopup(self),
           let requestedURL = request.url,
           let currentURL = url,
           currentURL == requestedURL,
           isLoading {
            return nil
        }

        return grokCompatibility_load(request)
    }
}
