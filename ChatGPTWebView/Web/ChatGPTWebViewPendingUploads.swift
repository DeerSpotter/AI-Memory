import UIKit
import UniformTypeIdentifiers
import WebKit

private final class WebViewOpenPanelDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: ([URL]?) -> Void

    init(completion: @escaping ([URL]?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}

private enum PendingUploadRegistry {
    static var pendingURLsByCoordinator: [ObjectIdentifier: [URL]] = [:]
    static var delegatesByCoordinator: [ObjectIdentifier: WebViewOpenPanelDelegate] = [:]
}

extension SecureChatGPTWebViewCoordinator {
    func setPendingUploadURLs(_ urls: [URL]) {
        let key = ObjectIdentifier(self)
        PendingUploadRegistry.pendingURLsByCoordinator[key] = urls
    }

    func hasPendingUploadURLs() -> Bool {
        let key = ObjectIdentifier(self)
        return !(PendingUploadRegistry.pendingURLsByCoordinator[key] ?? []).isEmpty
    }

    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let key = ObjectIdentifier(self)
        let pendingURLs = PendingUploadRegistry.pendingURLsByCoordinator[key] ?? []

        if !pendingURLs.isEmpty {
            PendingUploadRegistry.pendingURLsByCoordinator[key] = []
            let urls = parameters.allowsMultipleSelection ? pendingURLs : Array(pendingURLs.prefix(1))
            completionHandler(urls)
            return
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection

        let delegate = WebViewOpenPanelDelegate { urls in
            PendingUploadRegistry.delegatesByCoordinator[key] = nil
            completionHandler(urls)
        }

        PendingUploadRegistry.delegatesByCoordinator[key] = delegate
        picker.delegate = delegate

        guard let presenter = Self.topViewController() else {
            PendingUploadRegistry.delegatesByCoordinator[key] = nil
            completionHandler(nil)
            return
        }

        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        return topViewController(from: root)
    }

    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigation = controller as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }

        if let tab = controller as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }

        if let presented = controller?.presentedViewController {
            return topViewController(from: presented)
        }

        return controller
    }
}

@MainActor
extension ChatGPTWebViewStore {
    func startNewChatWithPendingUploadURLs(_ urls: [URL]) {
        coordinator.setPendingUploadURLs(urls)
        startNewChat()
    }

    func triggerPendingAttachmentPicker() async {
        guard coordinator.hasPendingUploadURLs() else { return }
        guard #available(iOS 18.4, *) else { return }

        try? await Task.sleep(nanoseconds: 1_200_000_000)

        guard coordinator.hasPendingUploadURLs() else { return }

        let script = #"""
        (() => {
          const input = document.querySelector('input[type="file"]');
          if (input) {
            input.click();
            return 'clicked-file-input';
          }

          const buttons = Array.from(document.querySelectorAll('button,[role="button"]'));
          const button = buttons.find((candidate) => {
            const label = [candidate.innerText, candidate.getAttribute('aria-label'), candidate.getAttribute('title')]
              .filter(Boolean)
              .join(' ')
              .toLowerCase();
            return label.includes('attach') || label.includes('upload') || label.includes('file') || label.includes('add');
          });

          if (button) {
            button.click();
            setTimeout(() => document.querySelector('input[type="file"]')?.click(), 350);
            return 'clicked-attach-button';
          }

          return 'no-file-control-found';
        })();
        """#

        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    func injectComposerText(_ text: String) async -> Bool {
        let encodedText: String
        if let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
           let json = String(data: data, encoding: .utf8) {
            encodedText = json
        } else {
            encodedText = "[\"\"]"
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        let script = """
        (() => {
          const text = \(encodedText)[0];

          const selectors = [
            'textarea',
            '[contenteditable="true"]',
            '.ProseMirror',
            '[data-testid="composer"] [contenteditable="true"]',
            '[data-testid="composer"] textarea',
            'form textarea',
            'form [contenteditable="true"]'
          ];

          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return r.width > 80 && r.height > 12 && style.visibility !== 'hidden' && style.display !== 'none';
          };

          const findComposer = () => {
            for (const selector of selectors) {
              const candidates = Array.from(document.querySelectorAll(selector)).filter(visible);
              if (candidates.length) return candidates[candidates.length - 1];
            }
            return null;
          };

          const tapLikeUser = (el) => {
            const r = el.getBoundingClientRect();
            const x = Math.max(1, Math.floor(r.left + Math.min(r.width - 1, 24)));
            const y = Math.max(1, Math.floor(r.top + Math.min(r.height - 1, Math.max(12, r.height / 2))));
            const opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            el.scrollIntoView({ block: 'center', inline: 'nearest' });
            el.dispatchEvent(new MouseEvent('mouseover', opts));
            el.dispatchEvent(new MouseEvent('mousedown', opts));
            el.dispatchEvent(new MouseEvent('mouseup', opts));
            el.dispatchEvent(new MouseEvent('click', opts));
            el.focus?.({ preventScroll: true });
          };

          const setNativeValue = (el, value) => {
            const proto = Object.getPrototypeOf(el);
            const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
            if (descriptor && descriptor.set) {
              descriptor.set.call(el, value);
            } else {
              el.value = value;
            }
          };

          const insertInto = (input) => {
            tapLikeUser(input);

            if (input.tagName === 'TEXTAREA' || input.tagName === 'INPUT') {
              setNativeValue(input, text);
              input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              return input.value === text || input.value.length > 0;
            }

            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(input);
            range.collapse(false);
            selection.removeAllRanges();
            selection.addRange(range);

            const inserted = document.execCommand && document.execCommand('insertText', false, text);
            if (!inserted) {
              input.textContent = text;
              input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
            }

            return (input.innerText || input.textContent || '').length > 0;
          };

          const directInput = findComposer();
          if (directInput && insertInto(directInput)) return true;

          const composerShell = Array.from(document.querySelectorAll('form, [data-testid="composer"], main'))
            .reverse()
            .find(visible);
          if (composerShell) {
            tapLikeUser(composerShell);
            const retryInput = findComposer();
            if (retryInput && insertInto(retryInput)) return true;
          }

          return false;
        })();
        """

        let value = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }

        return (value as? Bool) == true
    }

    func userMessageCount() async -> Int {
        let script = #"""
        (() => document.querySelectorAll('[data-message-author-role="user"]').length)();
        """#

        let value = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }

        if let intValue = value as? Int { return intValue }
        if let numberValue = value as? NSNumber { return numberValue.intValue }
        return 0
    }
}
