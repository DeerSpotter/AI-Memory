import Foundation
import WebKit

private enum ContextPortChatPerformanceScript {
    static let marker = "CONTEXT_PORT_CHAT_PERFORMANCE_V1"

    static func bootstrap(providerID: AIProviderID) -> String {
        #"""
        (() => {
          // CONTEXT_PORT_CHAT_PERFORMANCE_V1
          const managerKey = '__contextPortChatPerformance';
          if (window[managerKey]?.version === 1) return true;

          const providerID = '\#(providerID.rawValue)';
          const providerConfigs = {
            chatgpt: {
              messageTurn: 'section[data-testid^="conversation-turn-"]',
              scrollContainers: ['div[data-scroll-root]', 'main']
            },
            claude: {
              messageTurn: '[data-test-render-count]',
              scrollContainers: ['div[data-autoscroll-container]', '.overflow-y-scroll']
            },
            gemini: {
              messageTurn: 'user-query, model-response',
              scrollContainers: ['infinite-scroller[data-test-id="chat-history-container"]', 'infinite-scroller.chat-history']
            },
            grok: {
              messageTurn: '[data-testid="user-message"], [data-testid="assistant-message"]',
              scrollContainers: ['main']
            }
          };

          const site = providerConfigs[providerID];
          if (!site) return false;

          const hiddenClass = 'contextport-chat-hidden';
          const trackedAttribute = 'data-contextport-chat-message';
          const enabledStorageKey = 'contextport_chat_performance_enabled';
          const limitStorageKey = 'contextport_chat_performance_limit';
          const revealBatchSize = 10;
          const mutationDebounceMilliseconds = 120;

          let enabled = false;
          let visibleLimit = 20;
          let expandedLimit = 20;
          let hiddenCount = 0;
          let trackedMessages = [];
          let trackedElements = new Set();
          let observer = null;
          let pendingMutations = [];
          let mutationTimer = null;
          let refreshFrame = null;
          let scrollFrame = null;
          let revealLocked = false;
          let lastScrollTop = Number.POSITIVE_INFINITY;
          let lastConversationURL = location.href;

          const safeNumber = (value, fallback) => {
            const parsed = Number.parseInt(String(value ?? ''), 10);
            return Number.isFinite(parsed) ? parsed : fallback;
          };

          const normalizedLimit = (value) => {
            const clamped = Math.min(100, Math.max(5, safeNumber(value, 20)));
            return Math.round(clamped / 5) * 5;
          };

          const injectStyle = () => {
            if (document.getElementById('contextport-chat-performance-style')) return;
            const style = document.createElement('style');
            style.id = 'contextport-chat-performance-style';
            style.textContent =
              `.${hiddenClass}{display:none!important;}` +
              `[${trackedAttribute}]:not(.${hiddenClass}),` +
              `[${trackedAttribute}]:not(.${hiddenClass}) *` +
              `{content-visibility:visible!important;contain-intrinsic-size:auto!important;}`;
            (document.head || document.documentElement).appendChild(style);
          };

          const findScrollContainer = () => {
            for (const selector of site.scrollContainers) {
              try {
                const candidate = document.querySelector(selector);
                if (candidate) return candidate;
              } catch (_) {}
            }
            return document.scrollingElement || document.documentElement;
          };

          const scrollTopFor = (element) => {
            if (!element || element === document.documentElement || element === document.body || element === document.scrollingElement) {
              return window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
            }
            return element.scrollTop || 0;
          };

          const scrollHeightFor = (element) => {
            if (!element || element === document.documentElement || element === document.body || element === document.scrollingElement) {
              return Math.max(document.documentElement.scrollHeight || 0, document.body?.scrollHeight || 0);
            }
            return element.scrollHeight || 0;
          };

          const setScrollTop = (element, value) => {
            if (!element || element === document.documentElement || element === document.body || element === document.scrollingElement) {
              window.scrollTo(0, value);
            } else {
              element.scrollTop = value;
            }
          };

          const messageElementsFromNode = (node) => {
            if (!(node instanceof Element)) return [];
            const matches = [];
            try {
              if (node.matches(site.messageTurn)) matches.push(node);
              node.querySelectorAll(site.messageTurn).forEach((element) => matches.push(element));
            } catch (_) {}
            return matches;
          };

          const trackMessage = (element) => {
            if (!(element instanceof HTMLElement) || trackedElements.has(element)) return false;
            trackedElements.add(element);
            trackedMessages.push(element);
            element.setAttribute(trackedAttribute, 'true');
            return true;
          };

          const untrackMessage = (element) => {
            if (!trackedElements.has(element)) return false;
            trackedElements.delete(element);
            element.classList.remove(hiddenClass);
            element.removeAttribute('aria-hidden');
            element.removeAttribute(trackedAttribute);
            return true;
          };

          const restoreAllMessages = () => {
            for (const element of trackedMessages) {
              element.classList.remove(hiddenClass);
              element.removeAttribute('aria-hidden');
              element.removeAttribute(trackedAttribute);
            }
            trackedMessages = [];
            trackedElements.clear();
            hiddenCount = 0;
          };

          const scanCurrentMessages = () => {
            let changed = false;
            try {
              document.querySelectorAll(site.messageTurn).forEach((element) => {
                changed = trackMessage(element) || changed;
              });
            } catch (_) {}
            return changed;
          };

          const pruneDisconnectedMessages = () => {
            if (!trackedMessages.length) return;
            const remaining = [];
            for (const element of trackedMessages) {
              if (element.isConnected && element.matches?.(site.messageTurn)) {
                remaining.push(element);
              } else {
                untrackMessage(element);
              }
            }
            trackedMessages = remaining;
          };

          const checkConversationChange = () => {
            if (location.href === lastConversationURL) return false;
            lastConversationURL = location.href;
            expandedLimit = visibleLimit;
            lastScrollTop = Number.POSITIVE_INFINITY;
            return true;
          };

          const recalculateVisibility = () => {
            refreshFrame = null;
            if (!enabled) return;

            injectStyle();
            const conversationChanged = checkConversationChange();
            pruneDisconnectedMessages();
            if (conversationChanged || trackedMessages.length === 0) scanCurrentMessages();

            const activeLimit = Math.max(visibleLimit, expandedLimit);
            const total = trackedMessages.length;
            const hideBeforeIndex = Math.max(0, total - activeLimit);
            hiddenCount = hideBeforeIndex;

            for (let index = 0; index < total; index += 1) {
              const element = trackedMessages[index];
              const shouldHide = index < hideBeforeIndex;
              if (shouldHide) {
                if (!element.classList.contains(hiddenClass)) element.classList.add(hiddenClass);
                if (element.getAttribute('aria-hidden') !== 'true') element.setAttribute('aria-hidden', 'true');
              } else {
                if (element.classList.contains(hiddenClass)) element.classList.remove(hiddenClass);
                if (element.hasAttribute('aria-hidden')) element.removeAttribute('aria-hidden');
              }
            }
          };

          const scheduleVisibilityRefresh = () => {
            if (refreshFrame !== null) return;
            refreshFrame = requestAnimationFrame(recalculateVisibility);
          };

          const processMutations = () => {
            mutationTimer = null;
            const mutations = pendingMutations;
            pendingMutations = [];
            if (!enabled) return;

            let changed = checkConversationChange();
            const removed = new Set();

            for (const mutation of mutations) {
              mutation.addedNodes.forEach((node) => {
                for (const element of messageElementsFromNode(node)) {
                  changed = trackMessage(element) || changed;
                }
              });

              mutation.removedNodes.forEach((node) => {
                for (const element of messageElementsFromNode(node)) removed.add(element);
              });
            }

            if (removed.size > 0) {
              trackedMessages = trackedMessages.filter((element) => {
                if (!removed.has(element) && element.isConnected) return true;
                changed = untrackMessage(element) || changed;
                return false;
              });
            }

            if (changed) scheduleVisibilityRefresh();
          };

          const handleMutations = (mutations) => {
            if (!enabled) return;
            pendingMutations.push(...mutations);
            if (mutationTimer !== null) clearTimeout(mutationTimer);
            mutationTimer = setTimeout(processMutations, mutationDebounceMilliseconds);
          };

          const revealOlderMessages = () => {
            if (!enabled || hiddenCount <= 0 || revealLocked) return;
            revealLocked = true;

            const scrollContainer = findScrollContainer();
            const beforeHeight = scrollHeightFor(scrollContainer);
            const beforeTop = scrollTopFor(scrollContainer);

            expandedLimit = Math.min(trackedMessages.length, Math.max(expandedLimit, visibleLimit) + revealBatchSize);
            recalculateVisibility();

            requestAnimationFrame(() => {
              const heightDelta = Math.max(0, scrollHeightFor(scrollContainer) - beforeHeight);
              if (heightDelta > 0) setScrollTop(scrollContainer, beforeTop + heightDelta);
              lastScrollTop = scrollTopFor(scrollContainer);
              setTimeout(() => { revealLocked = false; }, 180);
            });
          };

          const handleScroll = () => {
            if (!enabled || hiddenCount <= 0 || revealLocked) return;
            if (scrollFrame !== null) cancelAnimationFrame(scrollFrame);
            scrollFrame = requestAnimationFrame(() => {
              scrollFrame = null;
              const scrollContainer = findScrollContainer();
              const currentTop = scrollTopFor(scrollContainer);
              const movingUp = currentTop < lastScrollTop - 2;
              lastScrollTop = currentTop;
              if (movingUp && currentTop <= 80) revealOlderMessages();
            });
          };

          const start = () => {
            if (observer || !document.body) return;
            injectStyle();
            scanCurrentMessages();
            observer = new MutationObserver(handleMutations);
            observer.observe(document.body, { childList: true, subtree: true });
            document.addEventListener('scroll', handleScroll, true);
            expandedLimit = Math.max(expandedLimit, visibleLimit);
            scheduleVisibilityRefresh();
          };

          const stop = () => {
            if (observer) observer.disconnect();
            observer = null;
            document.removeEventListener('scroll', handleScroll, true);
            if (mutationTimer !== null) clearTimeout(mutationTimer);
            mutationTimer = null;
            pendingMutations = [];
            if (refreshFrame !== null) cancelAnimationFrame(refreshFrame);
            refreshFrame = null;
            if (scrollFrame !== null) cancelAnimationFrame(scrollFrame);
            scrollFrame = null;
            revealLocked = false;
            restoreAllMessages();
          };

          const configure = (nextConfig = {}) => {
            const nextEnabled = Boolean(nextConfig.enabled);
            const nextLimit = normalizedLimit(nextConfig.limit);
            const limitChanged = nextLimit !== visibleLimit;

            visibleLimit = nextLimit;
            if (limitChanged) expandedLimit = visibleLimit;

            if (!nextEnabled) {
              enabled = false;
              stop();
              return getStatus();
            }

            enabled = true;
            if (!document.body) {
              document.addEventListener('DOMContentLoaded', start, { once: true });
            } else {
              start();
            }
            scheduleVisibilityRefresh();
            return getStatus();
          };

          const getStatus = () => ({
            version: 1,
            providerID,
            enabled,
            visibleMessageLimit: visibleLimit,
            expandedMessageLimit: expandedLimit,
            totalMessages: trackedMessages.length,
            visibleMessages: Math.max(0, trackedMessages.length - hiddenCount),
            hiddenMessages: hiddenCount
          });

          window[managerKey] = {
            version: 1,
            configure,
            getStatus,
            revealOlderMessages
          };

          let initialEnabled = false;
          let initialLimit = 20;
          try {
            initialEnabled = localStorage.getItem(enabledStorageKey) === 'true';
            initialLimit = normalizedLimit(localStorage.getItem(limitStorageKey));
          } catch (_) {}

          configure({ enabled: initialEnabled, limit: initialLimit });
          return true;
        })();
        """#
    }
}

@MainActor
extension ChatGPTWebViewStore {
    func applyChatPerformanceConfiguration(_ configuration: ChatPerformanceConfiguration) async {
        let controller = webView.configuration.userContentController
        let bootstrapScript = ContextPortChatPerformanceScript.bootstrap(providerID: provider.id)

        if !controller.userScripts.contains(where: { $0.source.contains(ContextPortChatPerformanceScript.marker) }) {
            controller.addUserScript(
                WKUserScript(
                    source: bootstrapScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        let shouldEnable = configuration.isEnabled(for: provider.id)
        let enabledValue = shouldEnable ? "true" : "false"
        let limit = configuration.visibleMessageLimit

        let configureScript = """
        (() => {
          try {
            localStorage.setItem('contextport_chat_performance_enabled', '\(enabledValue)');
            localStorage.setItem('contextport_chat_performance_limit', '\(limit)');
          } catch (_) {}

          if (!window.__contextPortChatPerformance) {
            \(bootstrapScript)
          }

          return window.__contextPortChatPerformance?.configure({
            enabled: \(enabledValue),
            limit: \(limit)
          }) ?? null;
        })();
        """

        _ = try? await evaluateChatPerformanceJavaScript(configureScript)
    }

    func chatPerformanceStatus() async -> [String: Any]? {
        let value = try? await evaluateChatPerformanceJavaScript(
            "window.__contextPortChatPerformance?.getStatus?.() ?? null"
        )
        return value as? [String: Any]
    }

    private func evaluateChatPerformanceJavaScript(_ script: String) async throws -> Any? {
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
}
