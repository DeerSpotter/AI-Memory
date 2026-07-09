from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one tail replacement anchor, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


# Insert conservative no-op DOM configurations using function boundaries rather
# than selector text, so Swift quote escaping cannot invalidate the applicator.
replace_once(
    'ChatGPTWebView/Web/ChatGPTWebViewChatPerformance.swift',
    '''        }
    }

    private static func javascriptArray(_ values: [String]) -> String {
''',
    '''        case .deepSeek:
            return ChatPerformanceDOMConfiguration(
                messageSelectors: [],
                scrollSelectors: []
            )
        }
    }

    private static func javascriptArray(_ values: [String]) -> String {
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTWebViewLatestExchange.swift',
    '''        }
    }

    private static func latestExchangeJavascriptArray(_ values: [String]) -> String {
''',
    '''        case .deepSeek:
            return LatestExchangeDOMConfiguration(
                messageSelectors: []
            )
        }
    }

    private static func latestExchangeJavascriptArray(_ values: [String]) -> String {
''',
)

replace_once(
    'ChatGPTWebView/Web/ChatGPTWebViewStore.swift',
    '''        if provider.id == .claude || provider.id == .grok {
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        }
''',
    '''        if provider.id == .claude || provider.id == .grok || provider.id == .deepSeek {
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        }
''',
)

replace_once(
    'project.yml',
    '''    MARKETING_VERSION: "2.8.0"
    CURRENT_PROJECT_VERSION: "67"
''',
    '''    MARKETING_VERSION: "2.9.0"
    CURRENT_PROJECT_VERSION: "68"
''',
)

checks = {
    'ChatGPTWebView/App/AIProvider.swift': [
        'case deepSeek = "deepseek"',
        '.deepSeek: AIProvider(',
        'https://chat.deepseek.com/sign_in',
    ],
    'ChatGPTWebView/App/AIProviderManager.swift': [
        'MultiAIDeepSeekProviderMigrationV1',
        'enabledIDs.insert(.deepSeek)',
    ],
    'ChatGPTWebView/App/RootView.swift': [
        'Text("Capture Required")',
        '.disabled(provider.id == .deepSeek)',
    ],
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift': [
        'provider-capture-required',
        'deepseek-source-capture-required',
        'deepseek: extractDeepSeek',
    ],
    'ChatGPTWebView/Web/ChatGPTWebViewChatPerformance.swift': ['case .deepSeek:'],
    'ChatGPTWebView/Web/ChatGPTWebViewLatestExchange.swift': ['case .deepSeek:'],
    'ChatGPTWebView/Web/ChatGPTWebViewStore.swift': ['provider.id == .deepSeek'],
    'project.yml': ['MARKETING_VERSION: "2.9.0"', 'CURRENT_PROJECT_VERSION: "68"'],
}

for path, markers in checks.items():
    text = (ROOT / path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'{path}: missing required DeepSeek marker {marker!r}')

print('DeepSeek tail patch applied and full source marker validation passed.')
