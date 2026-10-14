import XCTest
@testable import Codenotch

@MainActor
final class WikiVibeRecoveryTests: XCTestCase {
    private let account = WikiVibeAccount(id: 42, username: "fixture", email: "")
    private var transport: RecoveryTransport!
    private var session: URLSession!

    override func tearDown() {
        session?.invalidateAndCancel()
        super.tearDown()
    }

    private func coordinator(expired: Bool = false, steps: [RecoveryTransport.Step]) -> (WikiVibeAuthCoordinator, RecoveryStore) {
        transport = RecoveryTransport(steps: steps)
        RecoveryProtocol.transport = transport
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryProtocol.self]
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        let store = RecoveryStore(WikiVibeSession(accessToken: "old-access", refreshToken: "old-refresh",
                                                 expiresIn: expired ? 0 : 3600, account: account))
        return (WikiVibeAuthCoordinator(api: WikiVibeAuthAPI(session: session), store: store), store)
    }

    private var me: RecoveryTransport.Step {
        .json("/api/v1/auth/sso/me", #"{"code":0,"data":{"user":{"id":42,"username":"fixture"}}}"#)
    }
    private var settings: RecoveryTransport.Step {
        .json("/api/v1/settings/public", #"{"code":0,"data":{"balance_unit_name":"USD","balance_unit_symbol":"$"}}"#)
    }
    private var refresh: RecoveryTransport.Step {
        .json("/api/v1/auth/refresh", #"{"code":0,"data":{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}}"#)
    }
    private var profile: RecoveryTransport.Step {
        .json("/api/v1/user/profile", #"{"code":0,"data":{"balance":7.5,"bonus_balance":0}}"#)
    }

    func testOfflineThenStringCode401RenewsAndLoadsBalance() async {
        let (coordinator, store) = coordinator(steps: [
            me, .offline("/api/v1/settings/public"),
            settings, .response("/api/v1/user/profile", 401, #"{"code":"UNAUTHORIZED","message":"expired"}"#),
            refresh, settings, profile
        ])
        await coordinator.restore()
        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertNil(coordinator.wallet)
        XCTAssertNotNil(coordinator.walletError)

        await coordinator.loadWallet()
        coordinator.stopWalletPolling()
        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertEqual(coordinator.wallet?.regularText, "$7.50")
        XCTAssertEqual(coordinator.wallet?.bonusText, "$0.00")
        XCTAssertNil(coordinator.walletError)
        XCTAssertEqual(store.value?.refreshToken, "new-refresh")
        XCTAssertEqual(transport.remaining, 0)
    }

    func testExpiredSessionRestoredOfflineRecoversOnNextPoll() async {
        let (coordinator, store) = coordinator(expired: true, steps: [
            .offline("/api/v1/auth/refresh"), refresh, settings, profile
        ])
        await coordinator.restore()
        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertNotNil(coordinator.notice)
        await coordinator.loadWallet()
        coordinator.stopWalletPolling()
        XCTAssertEqual(coordinator.wallet?.regular, 7.5)
        XCTAssertNil(coordinator.notice)
        XCTAssertEqual(store.value?.refreshToken, "new-refresh")
        XCTAssertEqual(transport.remaining, 0)
    }

    func testHTML401RefreshRefusalRequiresSignIn() async {
        let (coordinator, store) = coordinator(steps: [
            me, settings, .response("/api/v1/user/profile", 401, "<html>expired</html>"),
            .response("/api/v1/auth/refresh", 401, "")
        ])
        await coordinator.restore()
        coordinator.stopWalletPolling()
        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(store.value)
        XCTAssertNil(coordinator.wallet)
        XCTAssertEqual(transport.remaining, 0)
    }

    func testRepeated401RetriesOnlyOnceThenSignsOut() async {
        let (coordinator, store) = coordinator(steps: [
            me, settings, .response("/api/v1/user/profile", 401, ""),
            refresh, settings, .response("/api/v1/user/profile", 401, "")
        ])
        await coordinator.restore()
        coordinator.stopWalletPolling()
        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(store.value)
        XCTAssertEqual(transport.remaining, 0)
    }

    func testRefreshNetworkFailureKeepsSessionAndNextPollRecovers() async {
        let (coordinator, store) = coordinator(steps: [
            me, settings, .response("/api/v1/user/profile", 401, ""),
            .offline("/api/v1/auth/refresh"),
            settings, .response("/api/v1/user/profile", 401, ""), refresh, settings, profile
        ])
        await coordinator.restore()
        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertEqual(store.value?.refreshToken, "old-refresh")
        await coordinator.loadWallet()
        coordinator.stopWalletPolling()
        XCTAssertEqual(coordinator.wallet?.regular, 7.5)
        XCTAssertNil(coordinator.walletError)
        XCTAssertEqual(store.value?.refreshToken, "new-refresh")
        XCTAssertEqual(transport.remaining, 0)
    }
}

private final class RecoveryStore: WikiVibeSessionStoreInterface {
    var value: WikiVibeSession?
    init(_ value: WikiVibeSession) { self.value = value }
    func load() -> WikiVibeSession? { value }
    func save(_ session: WikiVibeSession) -> Bool { value = session; return true }
    func clear() -> Bool { value = nil; return true }
}

private final class RecoveryTransport: @unchecked Sendable {
    enum Step {
        case response(String, Int, String)
        case offline(String)
        static func json(_ path: String, _ body: String) -> Step { .response(path, 200, body) }
    }
    private let lock = NSLock()
    private var steps: [Step]
    init(steps: [Step]) { self.steps = steps }
    var remaining: Int { lock.lock(); defer { lock.unlock() }; return steps.count }
    func next() -> Step? {
        lock.lock(); defer { lock.unlock() }
        return steps.isEmpty ? nil : steps.removeFirst()
    }
}

private final class RecoveryProtocol: URLProtocol, @unchecked Sendable {
    // XCTest executes this suite serially; each test owns its ephemeral session.
    static var transport: RecoveryTransport?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let step = Self.transport?.next() else {
            XCTFail("Unexpected recovery request")
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch step {
        case .offline(let path):
            XCTAssertEqual(request.url?.path, path)
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .response(let path, let status, let body):
            XCTAssertEqual(request.url?.path, path)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
