import Foundation
import WebKit

/// Compiles and caches the tracker/ad WKContentRuleList. Rules run inside
/// WebKit's network process, so blocked requests cost no JavaScript and no
/// main-thread time — they simply never happen.
@MainActor
final class ContentBlockerService {
    static let shared = ContentBlockerService()

    /// Bump the suffix whenever `blockedTrackerDomains` changes so the
    /// on-disk compiled cache is invalidated.
    private static let ruleListIdentifier = "LumaTrackerBlockRules-v1"

    private var cachedRuleList: WKContentRuleList?

    func ruleList() async -> WKContentRuleList? {
        if let cachedRuleList {
            return cachedRuleList
        }

        let ruleList = await loadOrCompileRuleList()
        cachedRuleList = ruleList
        return ruleList
    }

    private func loadOrCompileRuleList() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }

        if let compiled = await lookUpCompiledRuleList(in: store) {
            return compiled
        }

        return await compileRuleList(in: store)
    }

    private func lookUpCompiledRuleList(in store: WKContentRuleListStore) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: Self.ruleListIdentifier) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    private func compileRuleList(in store: WKContentRuleListStore) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: Self.ruleListIdentifier,
                encodedContentRuleList: Self.encodedRules()
            ) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    /// Third-party ad/tracking hosts only — first-party requests and
    /// login-critical hosts (e.g. connect.facebook.net) are left alone so
    /// sites keep working.
    private static let blockedTrackerDomains = [
        // Ad delivery and exchanges
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "googletagservices.com",
        "adservice.google.com",
        "amazon-adsystem.com",
        "adnxs.com",
        "adsrvr.org",
        "criteo.com",
        "criteo.net",
        "rubiconproject.com",
        "pubmatic.com",
        "openx.net",
        "casalemedia.com",
        "smartadserver.com",
        "spotxchange.com",
        "teads.tv",
        "sharethrough.com",
        "yieldmo.com",
        "33across.com",
        "bidswitch.net",
        "taboola.com",
        "outbrain.com",
        // Ad verification (heavy per-impression JavaScript)
        "moatads.com",
        "doubleverify.com",
        "adsafeprotected.com",
        // Analytics and audience tracking
        "google-analytics.com",
        "scorecardresearch.com",
        "quantserve.com",
        "demdex.net",
        "omtrdc.net",
        "krxd.net",
        "bluekai.com",
        "mathtag.com",
        "rlcdn.com",
        "agkn.com",
        "simpli.fi",
        "chartbeat.com",
        "mixpanel.com",
        "amplitude.com",
        // Session recording (continuous CPU while a page is open)
        "hotjar.com",
        "fullstory.com",
        "mouseflow.com",
        "clarity.ms"
    ]

    private static func encodedRules() -> String {
        let rules: [[String: Any]] = blockedTrackerDomains.map { domain in
            let escapedDomain = domain.replacingOccurrences(of: ".", with: "\\.")
            return [
                "trigger": [
                    "url-filter": "^https?://(.*\\.)?\(escapedDomain)[/:]",
                    "load-type": ["third-party"]
                ],
                "action": ["type": "block"]
            ]
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: rules),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return encoded
    }
}
