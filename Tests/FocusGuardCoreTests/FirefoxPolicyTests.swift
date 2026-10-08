import Testing
@testable import FocusGuardCore

@Suite("FirefoxPolicy")
struct FirefoxPolicyTests {
    @Test func addsExcludedDomainsSortedAndUnique() {
        let policy = FirefoxPolicy.dnsOverHTTPS(nil, excluding: ["youtube.com", "chess.com", "youtube.com"])
        #expect(FirefoxPolicy.excludedDomains(in: policy) == ["chess.com", "youtube.com"])
    }

    @Test func keepsOtherDNSOverHTTPSSettings() {
        let current: [String: Any] = ["ProviderURL": "https://dns.example/dns-query", "ExcludedDomains": ["old.com"]]
        let policy = FirefoxPolicy.dnsOverHTTPS(current, excluding: ["instagram.com"])
        #expect(policy?["ProviderURL"] as? String == "https://dns.example/dns-query")
        #expect(FirefoxPolicy.excludedDomains(in: policy) == ["instagram.com"])
    }

    @Test func emptyListRemovesOnlyOurKey() {
        let withProvider: [String: Any] = ["ProviderURL": "https://dns.example/dns-query", "ExcludedDomains": ["a.com"]]
        let kept = FirefoxPolicy.dnsOverHTTPS(withProvider, excluding: [])
        #expect(kept?["ProviderURL"] != nil)
        #expect(kept?["ExcludedDomains"] == nil)

        #expect(FirefoxPolicy.dnsOverHTTPS(["ExcludedDomains": ["a.com"]], excluding: []) == nil)
    }
}
