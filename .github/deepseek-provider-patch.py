from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one replacement anchor, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


# Provider catalog.
replace_once(
    'ChatGPTWebView/App/AIProvider.swift',
    '    case gemini\n    case grok\n',
    '    case gemini\n    case grok\n    case deepSeek = "deepseek"\n',
)
replace_once(
    'ChatGPTWebView/App/AIProvider.swift',
    '''            authenticatedHostSuffixes: ["grok.com"],
            unauthenticatedPathPrefixes: ["/login", "/signin", "/sign-in", "/auth"]
        )
    ]
}''',
    '''            authenticatedHostSuffixes: ["grok.com"],
            unauthenticatedPathPrefixes: ["/login", "/signin", "/sign-in", "/auth"]
        ),
        .deepSeek: AIProvider(
            id: .deepSeek,
            displayName: "DeepSeek",
            systemImage: "brain.head.profile",
            startURL: URL(string: "https://chat.deepseek.com/")!,
            loginURL: URL(string: "https://chat.deepseek.com/sign_in")!,
            allowedHostSuffixes: [
                "deepseek.com",
                "google.com",
                "gstatic.com",
                "googleusercontent.com",
                "apple.com",
                "icloud.com",
                "awswaf.com",
                "amazonaws.com"
            ],
            persistentCookieHostSuffixes: ["deepseek.com"],
            authenticatedHostSuffixes: ["chat.deepseek.com"],
            unauthenticatedPathPrefixes: ["/sign_in", "/signin", "/login", "/auth"]
        )
    ]
}''',
)

# One-time enablement migration. Existing users with all four legacy providers
# enabled receive DeepSeek automatically. Curated provider sets stay curated.
replace_once(
    'ChatGPTWebView/App/AIProviderManager.swift',
    '''    private static let activeProviderKey = "MultiAIActiveProviderID"
    private static let enabledProvidersKey = "MultiAIEnabledProviderIDs"
''',
    '''    private static let activeProviderKey = "MultiAIActiveProviderID"
    private static let enabledProvidersKey = "MultiAIEnabledProviderIDs"
    private static let deepSeekProviderMigrationKey = "MultiAIDeepSeekProviderMigrationV1"
''',
)
replace_once(
    'ChatGPTWebView/App/AIProviderManager.swift',
    '''        let storedEnabled = defaults.stringArray(forKey: Self.enabledProvidersKey) ?? []
        let decodedEnabled = Set(storedEnabled.compactMap(AIProviderID.init(rawValue:)))
        let enabledIDs = decodedEnabled.isEmpty ? Set(AIProviderID.allCases) : decodedEnabled
        self.enabledProviderIDs = enabledIDs
''',
    '''        let storedEnabled = defaults.stringArray(forKey: Self.enabledProvidersKey) ?? []
        let decodedEnabled = Set(storedEnabled.compactMap(AIProviderID.init(rawValue:)))
        var enabledIDs = decodedEnabled.isEmpty ? Set(AIProviderID.allCases) : decodedEnabled

        if !defaults.bool(forKey: Self.deepSeekProviderMigrationKey) {
            let legacyAllProviders: Set<AIProviderID> = [.chatGPT, .claude, .gemini, .grok]
            if decodedEnabled.isEmpty || decodedEnabled == legacyAllProviders {
                enabledIDs.insert(.deepSeek)
            }
            defaults.set(true, forKey: Self.deepSeekProviderMigrationKey)
            defaults.set(enabledIDs.map(\.rawValue).sorted(), forKey: Self.enabledProvidersKey)
        }

        self.enabledProviderIDs = enabledIDs
''',
)

# Keep unsupported performance features visibly unavailable until the real
# DeepSeek DOM is captured from a physical device.
replace_once(
    'ChatGPTWebView/App/RootView.swift',
    '''                                if provider.id == .grok {
                                    Text("Experimental")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
''',
    '''                                if provider.id == .grok {
                                    Text("Experimental")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if provider.id == .deepSeek {
                                    Text("Capture Required")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(provider.id == .deepSeek)
                    }
''',
)

# Save Context fails closed until DeepSeek's actual rendered role markers are captured.
replace_once(
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift',
    '''    case invalidConversationStructure
    case providerUIChanged(String)
''',
    '''    case invalidConversationStructure
    case providerCaptureRequired(String)
    case providerUIChanged(String)
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift',
    '''        case .invalidConversationStructure:
            return "ContextPort found conversation content but could not verify both a user turn and an AI response. Nothing was saved."
        case .providerUIChanged(let message):
''',
    '''        case .invalidConversationStructure:
            return "ContextPort found conversation content but could not verify both a user turn and an AI response. Nothing was saved."
        case .providerCaptureRequired(let providerName):
            return "Save Context for \(providerName) is intentionally disabled until ContextPort captures and verifies that provider's real conversation UI markers. Enable Developer Mode, open a short \(providerName) conversation, then save the loaded Sources to Memory for selector review."
        case .providerUIChanged(let message):
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift',
    '''        let payload = try JSONDecoder().decode(ChatConversationExportPayload.self, from: data)
        let turns = payload.turns.compactMap(validateTurn)
''',
    '''        let payload = try JSONDecoder().decode(ChatConversationExportPayload.self, from: data)
        if payload.error == "provider-capture-required" {
            throw ChatConversationExportError.providerCaptureRequired(provider.displayName)
        }

        let turns = payload.turns.compactMap(validateTurn)
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift',
    '''          const extractGemini = () => {
''',
    '''          const extractDeepSeek = () => ({
            turns: [],
            error: 'provider-capture-required',
            diagnostics: diagnostics(
              'deepseek-source-capture-required',
              ['deepseek-positive-role-evidence'],
              []
            )
          });
          const extractGemini = () => {
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift',
    '''            gemini: extractGemini,
            grok: extractGrok
''',
    '''            gemini: extractGemini,
            grok: extractGrok,
            deepseek: extractDeepSeek
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTConversationExporter.swift',
    '''          const error = blockingChallengeDetected ? 'security-interstitial' : null;
''',
    '''          const error = blockingChallengeDetected
            ? 'security-interstitial'
            : (extraction.error || null);
''',
)

# Explicit conservative no-op DOM configurations until source capture.
replace_once(
    'ChatGPTWebView/Web/ChatGPTWebViewChatPerformance.swift',
    '''        case .grok:
            return ChatPerformanceDOMConfiguration(
                messageSelectors: [
                    "main article",
                    "main [data-message-id]",
                    "main [data-testid*=\"message\"]"
                ],
                scrollSelectors: [
                    "main"
                ]
            )
        }
''',
    '''        case .grok:
            return ChatPerformanceDOMConfiguration(
                messageSelectors: [
                    "main article",
                    "main [data-message-id]",
                    "main [data-testid*=\"message\"]"
                ],
                scrollSelectors: [
                    "main"
                ]
            )
        case .deepSeek:
            return ChatPerformanceDOMConfiguration(
                messageSelectors: [],
                scrollSelectors: []
            )
        }
''',
)
replace_once(
    'ChatGPTWebView/Web/ChatGPTWebViewLatestExchange.swift',
    '''        case .grok:
            return LatestExchangeDOMConfiguration(
                messageSelectors: [
                    "main article",
                    "main [data-message-id]",
                    "main [data-testid*=\"message\"]"
                ]
            )
        }
''',
    '''        case .grok:
            return LatestExchangeDOMConfiguration(
                messageSelectors: [
                    "main article",
                    "main [data-message-id]",
                    "main [data-testid*=\"message\"]"
                ]
            )
        case .deepSeek:
            return LatestExchangeDOMConfiguration(
                messageSelectors: []
            )
        }
''',
)

# Keep DeepSeek JavaScript-auth windows inside the provider browsing context.
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

# Release/build bump.
replace_once(
    'project.yml',
    '''    MARKETING_VERSION: "2.8.0"
    CURRENT_PROJECT_VERSION: "67"
''',
    '''    MARKETING_VERSION: "2.9.0"
    CURRENT_PROJECT_VERSION: "68"
''',
)

# Strong post-patch assertions.
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
            raise SystemExit(f'{path}: missing required marker {marker!r}')

print('DeepSeek provider patch applied and validated.')
