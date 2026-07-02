import Foundation
import UIKit
import WebKit

struct ChatConversationExportResult {
    let title: String
    let messageCount: Int
    let markdownURL: URL
    let pdfURL: URL

    var shareURLs: [URL] {
        [markdownURL, pdfURL]
    }
}

enum ChatConversationExportError: LocalizedError {
    case invalidPayload
    case noMessagesFound
    case cannotCreatePDF

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "The ChatGPT page did not return a valid conversation export payload."
        case .noMessagesFound:
            return "No ChatGPT messages were found on the current page. Open a conversation and try again."
        case .cannotCreatePDF:
            return "The Markdown export was saved, but the PDF renderer could not create a PDF file."
        }
    }
}

private struct ChatConversationExportPayload: Decodable {
    let title: String
    let markdown: String
    let messageCount: Int
    let sourceURL: String
    let exportedAt: String
}

@MainActor
final class ChatGPTConversationExporter {
    private static let rootFolderName = "ChatGPT Context Exports"

    static func exportConversation(from webView: WKWebView) async throws -> ChatConversationExportResult {
        let rawResult = try await evaluateJavaScript(conversationExtractionJavaScript, in: webView)

        guard let jsonString = rawResult as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            throw ChatConversationExportError.invalidPayload
        }

        let payload = try JSONDecoder().decode(ChatConversationExportPayload.self, from: jsonData)
        let markdown = payload.markdown.trimmingCharacters(in: .whitespacesAndNewlines)

        guard payload.messageCount > 0, !markdown.isEmpty else {
            throw ChatConversationExportError.noMessagesFound
        }

        let safeTitle = safeFileName(payload.title)
        let outputDirectory = try conversationOutputDirectory(title: safeTitle)
        let timestamp = fileTimestampFormatter.string(from: Date())
        let baseName = "\(timestamp)_\(safeTitle)"

        let markdownURL = outputDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension("md")
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let printableHTML = renderPrintableHTML(title: payload.title,
                                                markdown: markdown,
                                                sourceURL: payload.sourceURL,
                                                exportedAt: payload.exportedAt,
                                                messageCount: payload.messageCount)
        let pdfData = try makePDFData(fromHTML: printableHTML)
        let pdfURL = outputDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension("pdf")
        try pdfData.write(to: pdfURL, options: .atomic)

        return ChatConversationExportResult(title: payload.title,
                                            messageCount: payload.messageCount,
                                            markdownURL: markdownURL,
                                            pdfURL: pdfURL)
    }

    private static func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: ChatConversationExportError.invalidPayload)
                }
            }
        }
    }

    private static func conversationOutputDirectory(title: String) throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportRootURL = documentsURL.appendingPathComponent(rootFolderName, isDirectory: true)
        let conversationURL = exportRootURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: conversationURL, withIntermediateDirectories: true)
        return conversationURL
    }

    private static func safeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = "ChatGPT Conversation"
        let compact = cleaned.isEmpty ? fallback : cleaned
        return String(compact.prefix(80))
    }

    private static var fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static func renderPrintableHTML(title: String,
                                            markdown: String,
                                            sourceURL: String,
                                            exportedAt: String,
                                            messageCount: Int) -> String {
        let escapedTitle = escapeHTML(title)
        let escapedMarkdown = escapeHTML(markdown)
        let escapedSourceURL = escapeHTML(sourceURL)
        let escapedExportedAt = escapeHTML(exportedAt)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, \"Helvetica Neue\", Arial, sans-serif;
              font-size: 12px;
              line-height: 1.45;
              color: #111;
            }
            h1 {
              font-size: 22px;
              margin-bottom: 6px;
            }
            .meta {
              color: #555;
              font-size: 10px;
              margin-bottom: 18px;
              word-break: break-word;
            }
            pre {
              white-space: pre-wrap;
              word-break: break-word;
              font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
              font-size: 10px;
            }
          </style>
        </head>
        <body>
          <h1>\(escapedTitle)</h1>
          <div class=\"meta\">
            Exported: \(escapedExportedAt)<br>
            Messages: \(messageCount)<br>
            Source: \(escapedSourceURL)
          </div>
          <pre>\(escapedMarkdown)</pre>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func makePDFData(fromHTML html: String) throws -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let printableRect = pageRect.insetBy(dx: 36, dy: 36)
        renderer.setValue(pageRect, forKey: "paperRect")
        renderer.setValue(printableRect, forKey: "printableRect")
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 0))

        guard renderer.numberOfPages > 0 else {
            throw ChatConversationExportError.cannotCreatePDF
        }

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, nil)
        for pageIndex in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: pageIndex, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        return data as Data
    }

    private static let conversationExtractionJavaScript = #"""
    (() => {
      const date = new Date().toISOString().slice(0, 10);
      const exportedAt = new Date().toISOString();
      const providerLabel = 'chatgpt.com';

      const normalize = (value) => String(value || '')
        .replace(/\u00a0/g, ' ')
        .replace(/\r\n?/g, '\n')
        .replace(/[ \t]+\n/g, '\n')
        .replace(/\n[ \t]+/g, '\n')
        .replace(/\n{3,}/g, '\n\n')
        .trim();

      const queryAll = (root, selector) => {
        try {
          return Array.from(root.querySelectorAll(selector));
        } catch (_) {
          return [];
        }
      };

      const topLevel = (elements) => elements.filter((element, index) =>
        !elements.some((other, otherIndex) => otherIndex !== index && other.contains(element))
      );

      const visibleText = (element) => normalize(element ? (element.innerText || element.textContent || '') : '');
      const score = (element) => visibleText(element).length + queryAll(element, 'pre, code-block, table, img, canvas, video, audio').length * 200;

      const detectTitle = () => {
        const selectors = [
          'h1:not([class*=\"hidden\"])',
          '[class*=\"conversation-title\"]',
          '[data-testid*=\"conversation-title\"]'
        ];
        for (const selector of selectors) {
          const text = normalize(document.querySelector(selector)?.textContent || '');
          if (text && !/^(chatgpt|new chat|untitled|chat)$/i.test(text)) return text;
        }
        const documentTitle = normalize(document.title || '').replace(/\s*[-|]\s*ChatGPT\s*$/i, '');
        return documentTitle && !/^(chatgpt|new chat|untitled|chat)$/i.test(documentTitle)
          ? documentTitle
          : 'ChatGPT Conversation';
      };

      const roleFor = (message, index) => {
        const roleElement = message.matches?.('[data-message-author-role]')
          ? message
          : message.querySelector?.('[data-message-author-role]');
        const role = (roleElement?.getAttribute('data-message-author-role') || '').toLowerCase();
        if (role === 'user') return { sender: 'You', type: 'user' };
        if (role === 'assistant') return { sender: 'ChatGPT', type: 'assistant' };
        const attributes = [message.className, message.getAttribute?.('aria-label'), message.getAttribute?.('data-testid')]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();
        if (/\b(user|human)\b/.test(attributes)) return { sender: 'You', type: 'user' };
        if (/\b(assistant|response|chatgpt)\b/.test(attributes)) return { sender: 'ChatGPT', type: 'assistant' };
        return index % 2 === 0 ? { sender: 'You', type: 'user' } : { sender: 'ChatGPT', type: 'assistant' };
      };

      const contentRootFor = (message) => {
        const roleElement = message.matches?.('[data-message-author-role]')
          ? message
          : message.querySelector?.('[data-message-author-role]');
        if (roleElement) return roleElement;

        const candidates = [message]
          .concat(queryAll(message, '.markdown, .prose, [class*=\"markdown\"], [class*=\"prose\"], [data-message-content], [data-testid*=\"content\"]'));
        return candidates.sort((a, b) => score(b) - score(a))[0] || message;
      };

      const isValidMessage = (element) => {
        if (!element) return false;
        if (element.matches?.('nav, aside, header, footer, form, menu')) return false;
        const textLength = visibleText(element).length;
        const richCount = queryAll(element, 'pre, code-block, table, img, canvas, video, audio').length;
        if (textLength < 5 && richCount === 0) return false;
        if (textLength > 300000) return false;
        if (element.querySelector?.('textarea, input[type=\"text\"], [contenteditable=\"true\"]') && !element.hasAttribute('data-message-author-role')) return false;
        return true;
      };

      const findMessages = () => {
        const selectors = [
          'div[data-message-author-role]',
          'article[data-testid*=\"conversation-turn\"]',
          'div[data-testid=\"conversation-turn\"]',
          '.group\\/conversation-turn',
          '[data-testid*=\"message\"], [data-message-id], [data-message-author]'
        ];

        for (const selector of selectors) {
          const messages = topLevel(queryAll(document, selector)).filter(isValidMessage);
          if (messages.length > 0) return messages;
        }

        const container = document.querySelector('[role=\"main\"], main, [class*=\"conversation\"], [class*=\"chat\"]') || document.body;
        return topLevel(Array.from(container.children || [])).filter(isValidMessage);
      };

      const fenceFor = (code) => {
        const runs = String(code || '').match(/`{3,}/g) || [];
        const longest = runs.reduce((max, run) => Math.max(max, run.length), 2);
        return '`'.repeat(longest + 1);
      };

      const languageFor = (block) => {
        const code = block.matches?.('code') ? block : block.querySelector?.('code');
        const sources = [
          code?.className,
          block.getAttribute?.('data-language'),
          block.getAttribute?.('language'),
          code?.getAttribute?.('data-language'),
          code?.getAttribute?.('language'),
          block.getAttribute?.('aria-label')
        ].filter(Boolean).map(String);

        for (const source of sources) {
          const match = source.match(/language-([a-zA-Z0-9_+#.-]+)/);
          if (match) return match[1].toLowerCase();
          if (/^[a-zA-Z0-9_+#.-]{1,24}$/.test(source) && !/^(code|copy|download)$/i.test(source)) return source.toLowerCase();
        }
        return '';
      };

      const codeTextFor = (block) => {
        const cmLines = queryAll(block, '.cm-content .cm-line');
        if (cmLines.length > 0) return cmLines.map((line) => line.textContent || '').join('\n');
        const code = block.matches?.('code') ? block : block.querySelector?.('code');
        return (code?.innerText || code?.textContent || block.innerText || block.textContent || '').replace(/\u00a0/g, ' ').trimEnd();
      };

      const tableToMarkdown = (table) => {
        const rows = Array.from(table.querySelectorAll('tr'))
          .map((row) => Array.from(row.children)
            .filter((cell) => ['TH', 'TD'].includes(cell.tagName))
            .map((cell) => normalize(cell.innerText || cell.textContent || '').replace(/\|/g, '\\|') || ' '))
          .filter((row) => row.length > 0);
        if (rows.length === 0) return normalize(table.innerText || table.textContent || '');
        const width = Math.max(...rows.map((row) => row.length));
        const normalizedRows = rows.map((row) => row.concat(Array(Math.max(0, width - row.length)).fill(' ')));
        const header = normalizedRows[0];
        const separator = header.map(() => '---');
        const body = normalizedRows.slice(1);
        return [
          `| ${header.join(' | ')} |`,
          `| ${separator.join(' | ')} |`,
          ...body.map((row) => `| ${row.join(' | ')} |`)
        ].join('\n');
      };

      const serializeContent = (root) => {
        const clone = root.cloneNode(true);
        queryAll(clone, [
          'button',
          'svg',
          'style',
          'script',
          'textarea',
          'input',
          '[contenteditable=\"true\"]',
          '[aria-label*=\"Copy\"]',
          '[aria-label*=\"copy\"]',
          '[aria-label*=\"More\"]',
          '[aria-label*=\"more\"]',
          '[data-testid*=\"copy\"]',
          '[data-test-id*=\"copy\"]'
        ].join(',')).forEach((node) => node.remove());

        topLevel(queryAll(clone, 'pre, code-block, [data-testid*=\"code-block\"], [data-test-id*=\"code-block\"]')).forEach((block) => {
          const code = codeTextFor(block);
          const language = languageFor(block).replace(/[^a-zA-Z0-9_+#.-]/g, '');
          const fence = fenceFor(code);
          block.replaceWith(document.createTextNode(`\n\n${fence}${language}\n${code}\n${fence}\n\n`));
        });

        topLevel(queryAll(clone, 'table')).forEach((table) => {
          table.replaceWith(document.createTextNode(`\n\n${tableToMarkdown(table)}\n\n`));
        });

        queryAll(clone, 'a[href]').forEach((link) => {
          const href = String(link.href || link.getAttribute('href') || '').trim();
          if (!href || /^(javascript|data|vbscript):/i.test(href)) return;
          const text = normalize(link.innerText || link.textContent || href);
          link.replaceWith(document.createTextNode(`[${text.replace(/[\[\]]/g, '\\$&')}](${href.replace(/\)/g, '%29')})`));
        });

        queryAll(clone, 'img, canvas, video, audio').forEach((media) => {
          const tag = media.tagName.toLowerCase();
          const alt = normalize(media.getAttribute('alt') || media.getAttribute('aria-label') || media.getAttribute('title') || '');
          const label = tag === 'img' && alt ? `[Image: ${alt}]` : tag === 'img' ? '[Image]' : tag === 'canvas' ? '[Canvas or chart]' : tag === 'video' ? '[Video]' : '[Audio]';
          media.replaceWith(document.createTextNode(label));
        });

        return normalize(clone.innerText || clone.textContent || '');
      };

      const rawMessages = findMessages();
      const seen = new Set();
      const messages = [];

      rawMessages.forEach((message, index) => {
        const contentRoot = contentRootFor(message);
        const content = serializeContent(contentRoot);
        if (!content || normalize(content).length < 5) return;
        const role = roleFor(message, index);
        const hash = `${role.type}:${normalize(content).slice(0, 220)}`;
        if (seen.has(hash)) return;
        seen.add(hash);
        messages.push({ sender: role.sender, type: role.type, content });
      });

      const title = detectTitle();
      const header = [
        `# ${title}`,
        '',
        `**Date:** ${date}`,
        `**Source:** ${providerLabel}`,
        `**Messages:** ${messages.length}`,
        '',
        '---',
        ''
      ];

      const body = messages.flatMap((message) => [
        `### **${message.sender}**`,
        '',
        message.content,
        '',
        '---',
        ''
      ]);

      return JSON.stringify({
        title,
        markdown: header.concat(body).join('\n').trim() + '\n',
        messageCount: messages.length,
        sourceURL: window.location.href || '',
        exportedAt
      });
    })();
    """#
}

@MainActor
extension ChatGPTWebViewStore {
    func exportCurrentConversation() async throws -> ChatConversationExportResult {
        try await ChatGPTConversationExporter.exportConversation(from: webView)
    }
}
