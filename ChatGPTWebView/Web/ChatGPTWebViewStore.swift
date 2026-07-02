import Foundation
import UIKit
import WebKit

struct ChatGPTPDFExport {
    let title: String
    let sourceURL: String?
    let data: Data
}

private struct ChatGPTScrollMetrics {
    let scrollHeight: CGFloat
    let clientHeight: CGFloat
    let maxScroll: CGFloat
    let originalScrollTop: CGFloat
}

@MainActor
final class ChatGPTWebViewStore: ObservableObject {
    let webView: WKWebView
    let coordinator: SecureChatGPTWebViewCoordinator
    private let startURL: URL

    init(startURL: URL = URL(string: "https://chatgpt.com/")!) {
        self.startURL = startURL
        self.coordinator = SecureChatGPTWebViewCoordinator()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

        self.webView = webView
    }

    func loadIfNeeded() {
        guard webView.url == nil, !webView.isLoading else {
            return
        }

        webView.load(URLRequest(url: startURL))
    }

    func stopCurrentActivity() {
        webView.stopLoading()
    }

    func reloadCurrentSession() {
        if webView.isLoading {
            webView.stopLoading()
        }

        if webView.url == nil {
            webView.load(URLRequest(url: startURL))
        } else {
            webView.reload()
        }
    }

    func startNewChat() {
        if webView.isLoading {
            webView.stopLoading()
        }
        webView.load(URLRequest(url: startURL))
    }

    func exportCurrentPagePDF() async throws -> ChatGPTPDFExport {
        let title = cleanTitle(webView.title)
        let sourceURL = webView.url?.absoluteString
        let metrics = try await prepareFullChatExport()
        defer {
            Task { @MainActor in
                try? await restoreChatScroll(to: metrics.originalScrollTop)
            }
        }

        let data = try await renderFullScrollPDF(title: title, metrics: metrics)
        return ChatGPTPDFExport(title: title, sourceURL: sourceURL, data: data)
    }

    private func prepareFullChatExport() async throws -> ChatGPTScrollMetrics {
        let script = """
        (() => {
          function visibleArea(el) {
            const r = el.getBoundingClientRect();
            return Math.max(0, r.width) * Math.max(0, r.height);
          }

          const candidates = [document.scrollingElement, document.documentElement, document.body]
            .concat(Array.from(document.querySelectorAll('main, [role="main"], div, section')))
            .filter(Boolean);

          let best = document.scrollingElement || document.documentElement || document.body;
          let bestScore = 0;

          for (const el of candidates) {
            const scrollHeight = Number(el.scrollHeight || 0);
            const clientHeight = Number(el.clientHeight || 0);
            const maxScroll = scrollHeight - clientHeight;
            if (scrollHeight < 800 || maxScroll < 80) continue;

            const area = visibleArea(el);
            const score = scrollHeight + area / 1000 + maxScroll * 3;
            if (score > bestScore) {
              best = el;
              bestScore = score;
            }
          }

          window.__chatgptFullChatExportTarget = best;
          window.__chatgptFullChatExportOriginalScrollTop = Number(best.scrollTop || window.scrollY || 0);
          best.scrollTop = 0;
          if (best === document.scrollingElement || best === document.documentElement || best === document.body) {
            window.scrollTo(0, 0);
          }

          return JSON.stringify({
            scrollHeight: Number(best.scrollHeight || document.documentElement.scrollHeight || document.body.scrollHeight || 0),
            clientHeight: Number(best.clientHeight || window.innerHeight || 0),
            maxScroll: Math.max(0, Number((best.scrollHeight || 0) - (best.clientHeight || window.innerHeight || 0))),
            originalScrollTop: Number(window.__chatgptFullChatExportOriginalScrollTop || 0)
          });
        })();
        """

        let value = try await evaluateStringJavaScript(script)
        guard let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ChatGPTPDFExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read chat scroll metrics."])
        }

        let scrollHeight = CGFloat((object["scrollHeight"] as? NSNumber)?.doubleValue ?? 0)
        let clientHeight = CGFloat((object["clientHeight"] as? NSNumber)?.doubleValue ?? 0)
        let maxScroll = CGFloat((object["maxScroll"] as? NSNumber)?.doubleValue ?? max(0, scrollHeight - clientHeight))
        let originalScrollTop = CGFloat((object["originalScrollTop"] as? NSNumber)?.doubleValue ?? 0)

        try await waitForScrollSettle()
        return ChatGPTScrollMetrics(
            scrollHeight: max(scrollHeight, webView.bounds.height),
            clientHeight: max(clientHeight, webView.bounds.height),
            maxScroll: max(0, maxScroll),
            originalScrollTop: originalScrollTop
        )
    }

    private func renderFullScrollPDF(title: String, metrics: ChatGPTScrollMetrics) async throws -> Data {
        let bounds = webView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            throw NSError(domain: "ChatGPTPDFExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "WebView is not ready to export."])
        }

        let pageRect = CGRect(origin: .zero, size: bounds.size)
        let step = max(120, bounds.height - 80)
        let pageCount = max(1, Int(ceil((metrics.maxScroll + bounds.height) / step)))
        let pdfData = NSMutableData()

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, [
            kCGPDFContextTitle as String: title,
            kCGPDFContextAuthor as String: "ChatGPTWebView Local PDF Context Memory",
            kCGPDFContextCreator as String: "ChatGPTWebView"
        ])
        defer { UIGraphicsEndPDFContext() }

        for pageIndex in 0..<pageCount {
            let offset = min(CGFloat(pageIndex) * step, metrics.maxScroll)
            try await setChatScrollTop(offset)
            try await waitForScrollSettle()
            let image = try await snapshotVisibleWebView()

            UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
            image.draw(in: pageRect)
        }

        if metrics.maxScroll > 0 {
            try await setChatScrollTop(metrics.maxScroll)
            try await waitForScrollSettle()
            let image = try await snapshotVisibleWebView()
            UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
            image.draw(in: pageRect)
        }

        return pdfData as Data
    }

    private func setChatScrollTop(_ offset: CGFloat) async throws {
        let script = """
        (() => {
          const target = window.__chatgptFullChatExportTarget || document.scrollingElement || document.documentElement || document.body;
          const y = \(Double(offset));
          target.scrollTop = y;
          if (target === document.scrollingElement || target === document.documentElement || target === document.body) {
            window.scrollTo(0, y);
          }
          return true;
        })();
        """
        _ = try await evaluateJavaScript(script)
    }

    private func restoreChatScroll(to offset: CGFloat) async throws {
        try await setChatScrollTop(offset)
    }

    private func snapshotVisibleWebView() async throws -> UIImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = true

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "ChatGPTPDFExport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to capture chat page snapshot."]))
                }
            }
        }
    }

    private func waitForScrollSettle() async throws {
        try await Task.sleep(nanoseconds: 180_000_000)
    }

    private func evaluateStringJavaScript(_ script: String) async throws -> String {
        let value = try await evaluateJavaScript(script)
        if let string = value as? String {
            return string
        }
        throw NSError(domain: "ChatGPTPDFExport", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected JavaScript result."])
    }

    private func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private func cleanTitle(_ value: String?) -> String {
        let trimmed = (value ?? "")
            .replacingOccurrences(of: "ChatGPT - ", with: "")
            .replacingOccurrences(of: " - ChatGPT", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty && trimmed.lowercased() != "chatgpt" {
            return trimmed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "ChatGPT chat \(formatter.string(from: Date()))"
    }
}

final class SecureChatGPTWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let allowedHostSuffixes = [
        "chatgpt.com",
        "openai.com",
        "oaistatic.com",
        "oaiusercontent.com",
        "auth0.com",
        "google.com",
        "gstatic.com",
        "googleusercontent.com",
        "apple.com",
        "icloud.com",
        "microsoft.com",
        "microsoftonline.com",
        "live.com",
        "microsoftonline.com",
        "live.com",
        "msauth.net"
    ]

    private let internalSchemes = [
        "https",
        "about",
        "blob",
        "data"
    ]

    private let externalSchemes = [
        "http",
        "https",
        "mailto",
        "tel",
        "sms"
    ]

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if isAllowedInsideWebView(url: url) {
            decisionHandler(.allow)
            return
        }

        if shouldOpenExternally(url: url, navigationAction: navigationAction) {
            openExternally(url)
        }

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else {
            return nil
        }

        if isAllowedInsideWebView(url: url) {
            webView.load(URLRequest(url: url))
        } else if shouldOpenExternally(url: url, navigationAction: navigationAction) {
            openExternally(url)
        }

        return nil
    }

    private func isAllowedInsideWebView(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), internalSchemes.contains(scheme) else {
            return false
        }

        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return true
        }

        guard scheme == "https", let host = url.host?.lowercased() else {
            return false
        }

        return allowedHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

    private func shouldOpenExternally(url: URL, navigationAction: WKNavigationAction) -> Bool {
        guard let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) else {
            return false
        }

        if isAllowedInsideWebView(url: url) {
            return false
        }

        switch navigationAction.navigationType {
        case .linkActivated, .formSubmitted, .other:
            return true
        default:
            return navigationAction.targetFrame == nil
        }
    }

    private func openExternally(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
}
