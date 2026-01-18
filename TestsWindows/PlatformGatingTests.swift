import CodexBarCore
import Testing

@Suite("Windows Platform Tests")
struct WindowsPlatformGatingTests {
    @Test
    func claudeWebFetcher_isNotSupportedOnWindows() async {
        #if os(Windows)
        let error = await #expect(throws: ClaudeWebAPIFetcher.FetchError.self) {
            _ = try await ClaudeWebAPIFetcher.fetchUsage()
        }
        let isExpectedError = error.map { thrown in
            if case .notSupportedOnThisPlatform = thrown { return true }
            return false
        } ?? false
        #expect(isExpectedError)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test
    func claudeWebFetcher_hasSessionKey_isFalseOnWindows() {
        #if os(Windows)
        #expect(ClaudeWebAPIFetcher.hasSessionKey(cookieHeader: nil) == false)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test
    func claudeWebFetcher_sessionKeyInfo_throwsOnWindows() {
        #if os(Windows)
        let error = #expect(throws: ClaudeWebAPIFetcher.FetchError.self) {
            _ = try ClaudeWebAPIFetcher.sessionKeyInfo()
        }
        let isExpectedError = error.map { thrown in
            if case .notSupportedOnThisPlatform = thrown { return true }
            return false
        } ?? false
        #expect(isExpectedError)
        #else
        #expect(Bool(true))
        #endif
    }
}
