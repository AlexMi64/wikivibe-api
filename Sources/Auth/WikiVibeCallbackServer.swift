import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// What a request to the loopback callback turned out to be.
///
/// Split out from the server so the parsing rules — which is the part with
/// security consequences — can be exercised without opening a socket.
enum WikiVibeCallbackRequest: Equatable {
    /// The server sent us a code for this attempt.
    case authorized(code: String)
    /// The server refused, or the user cancelled. Its own error name is kept.
    case denied(String)
    /// A callback carrying a different `state`. Not this attempt, so not ours
    /// to consume: the listener stays open for the real one.
    case mismatch
    /// Our path, but nothing usable in it.
    case malformed(String)
    /// Some other path — a favicon, a stray probe. Ignored.
    case notFound
}

/// How a sign-in attempt ended.
///
/// Distinct from `WikiVibeCallbackRequest` because two of these cannot come
/// from a request at all, and a handler that had to answer for them anyway
/// would be describing states it can never see.
enum WikiVibeCallbackOutcome: Equatable {
    case authorized(code: String)
    case denied(String)
    case mismatch
    case malformed(String)
    /// The user never came back inside the window.
    case timedOut
    /// The attempt was abandoned locally: another sign-in started, or the app
    /// is shutting the listener down.
    case cancelled
}

extension WikiVibeCallbackRequest {
    /// The outcome this request settles, or nil when it is not ours to settle.
    ///
    /// `notFound` is the browser asking for something else on this port, and
    /// `mismatch` belongs to a different attempt — answering either as this
    /// attempt's result would end the wait on the wrong request.
    var settlesAs: WikiVibeCallbackOutcome? {
        switch self {
        case .authorized(let code): return .authorized(code: code)
        case .denied(let reason): return .denied(reason)
        case .malformed(let reason): return .malformed(reason)
        case .mismatch, .notFound: return nil
        }
    }
}

/// The query half of the authorization callback.
enum WikiVibeCallbackQuery {
    /// Parse a callback request URI against the `state` this attempt sent.
    ///
    /// The state check lives here rather than in the caller because it decides
    /// whether the listener is finished. A callback whose state differs belongs
    /// to a different authorization attempt — a second window, an old tab — and
    /// treating it as the answer to this one would let anything that can reach
    /// loopback feed the app an arbitrary code.
    static func parse(uri: String, expectedState: String) -> WikiVibeCallbackRequest {
        guard let components = URLComponents(string: uri) else {
            return .mismatch
        }
        guard components.path == WikiVibeAuthContract.callbackPath else {
            return .notFound
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value,
                  !raw.isEmpty
            else { return nil }
            return raw
        }

        guard let state = value("state") else {
            return .mismatch
        }
        guard state == expectedState else { return .mismatch }
        if let error = value("error") {
            return .denied(value("error_description") ?? error)
        }
        guard let code = value("code") else {
            return .malformed("missing code")
        }
        return .authorized(code: code)
    }
}

/// A one-shot HTTP listener on `127.0.0.1` that catches the browser's return.
///
/// Sign-in happens in the system browser, so the only way back into the app is
/// something the browser can reach. A loopback socket is the whole of it: the
/// app asks the OS for a free port, registers nothing with the system, and
/// serves exactly one request before closing. It answers on the registered path
/// only, so the browser's own `favicon.ico` request is ignored rather than
/// mistaken for a callback.
///
/// The listener is not a service: it exists for the length of one sign-in and
/// is closed by `stop()` on every path out, including timeout and cancellation.
final class WikiVibeCallbackServer: @unchecked Sendable {
    /// The port the OS handed out. Goes into the registered redirect URI.
    let port: Int

    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let collector: WikiVibeCallbackCollector
    private var stopped = false

    private init(group: MultiThreadedEventLoopGroup,
                 channel: Channel,
                 collector: WikiVibeCallbackCollector,
                 port: Int) {
        self.group = group
        self.channel = channel
        self.collector = collector
        self.port = port
    }

    /// Bind a loopback listener and return it with the port it got.
    ///
    /// `port: 0` is deliberate — a fixed port would fail whenever something
    /// else on the machine already holds it, and the server accepts any port
    /// for this client precisely so that does not have to happen.
    static func start(expectedState: String) async throws -> WikiVibeCallbackServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: WikiVibeCallbackOutcome.self)
        let collector = WikiVibeCallbackCollector(promise: promise)

        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { @Sendable channel in
                    channel.pipeline.configureHTTPServerPipeline(
                        withPipeliningAssistance: false,
                        withErrorHandling: true
                    ).flatMap { @Sendable () -> EventLoopFuture<Void> in
                        channel.pipeline.addHandler(WikiVibeCallbackHandler(expectedState: expectedState, collector: collector))
                    }
                }
                .bind(host: WikiVibeAuthContract.callbackHost, port: 0)
                .get()
            guard let port = channel.localAddress?.port else {
                try? await channel.close().get()
                try? await group.shutdownGracefully()
                throw WikiVibeAuthError.couldNotListen("loopback port unavailable")
            }
            return WikiVibeCallbackServer(group: group, channel: channel, collector: collector, port: port)
        } catch let error as WikiVibeAuthError {
            try? await group.shutdownGracefully()
            throw error
        } catch {
            try? await group.shutdownGracefully()
            throw WikiVibeAuthError.couldNotListen(error.localizedDescription)
        }
    }

    /// Wait for the browser to come back, or give up.
    ///
    /// The deadline is enforced on the listener's own event loop so a browser
    /// the user closed without cancelling cannot leave the app waiting for a
    /// callback that will never arrive.
    func waitForCallback(timeout: TimeInterval) async throws -> WikiVibeCallbackOutcome {
        let deadline = channel.eventLoop.scheduleTask(in: .seconds(Int64(timeout.rounded()))) {
            _ = self.collector.finish(.timedOut)
        }
        defer { deadline.cancel() }
        return try await collector.outcome.futureResult.get()
    }

    /// Close the listener. Safe to call more than once and from any path out.
    func stop() async {
        guard !stopped else { return }
        stopped = true
        _ = collector.finish(.cancelled)
        try? await channel.close().get()
        try? await group.shutdownGracefully()
    }
}

/// Holds the single outcome the listener is waiting for.
///
/// More than one request can reach the port before sign-in finishes, and the
/// promise underneath accepts exactly one result, so the first decision wins
/// under a lock instead of racing.
private final class WikiVibeCallbackCollector: @unchecked Sendable {
    let outcome: EventLoopPromise<WikiVibeCallbackOutcome>
    private let lock = NSLock()
    private var settled = false

    init(promise: EventLoopPromise<WikiVibeCallbackOutcome>) {
        self.outcome = promise
    }

    /// Settle the wait, once. Returns false if it was already settled.
    @discardableResult
    func finish(_ result: WikiVibeCallbackOutcome) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return false }
        settled = true
        outcome.succeed(result)
        return true
    }
}

/// Serves the callback page and hands the result to the collector.
private final class WikiVibeCallbackHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let expectedState: String
    private let collector: WikiVibeCallbackCollector
    private var request: HTTPRequestHead?

    init(expectedState: String, collector: WikiVibeCallbackCollector) {
        self.expectedState = expectedState
        self.collector = collector
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            request = head
        case .body:
            break
        case .end:
            guard let head = request else { return }
            request = nil
            respond(to: head, context: context)
        }
    }

    private func respond(to head: HTTPRequestHead, context: ChannelHandlerContext) {
        // Only a GET can be the browser's return; anything else on this port is
        // not our callback and must not settle the wait.
        guard head.method == .GET else {
            respond(status: .methodNotAllowed, title: L10n.t("Nothing to see here."),
                    message: "", context: context, settleAs: nil)
            return
        }

        let result = WikiVibeCallbackQuery.parse(uri: head.uri, expectedState: expectedState)
        switch result {
        case .notFound:
            respond(status: .notFound, title: L10n.t("Nothing to see here."),
                    message: "", context: context, settleAs: nil)
        case .mismatch:
            // A callback for a different attempt. Answering it does not end
            // this one: the real return may still be on its way.
            respond(status: .badRequest, title: L10n.t("Sign-in could not be completed."),
                    message: L10n.t("This response did not come from the sign-in that is waiting."),
                    context: context, settleAs: nil)
        case .malformed(let reason):
            respond(status: .badRequest, title: L10n.t("Sign-in could not be completed."),
                    message: reason, context: context, settleAs: result.settlesAs)
        case .denied, .authorized:
            respond(status: .ok, title: L10n.t("You can close this tab."),
                    message: L10n.t("WikiVibe is finishing sign-in."),
                    context: context, settleAs: result.settlesAs)
        }
    }

    private func respond(status: HTTPResponseStatus,
                         title: String,
                         message: String,
                         context: ChannelHandlerContext,
                         settleAs outcome: WikiVibeCallbackOutcome?) {
        if let outcome { collector.finish(outcome) }

        let body = Self.page(title: title, message: message)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
        headers.add(name: "Content-Length", value: String(body.utf8.count))
        headers.add(name: "Cache-Control", value: "no-store")
        // The page is the app's own, and the code in the URL must not travel on
        // as a referrer if the user follows a link from it.
        headers.add(name: "Referrer-Policy", value: "no-referrer")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private static func page(title: String, message: String) -> String {
        // Escaped because the message can carry a server-supplied reason.
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <title>\(escaped(title))</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { font: 15px/1.5 -apple-system, system-ui, sans-serif; margin: 0;
               display: flex; min-height: 100vh; align-items: center; justify-content: center; }
        main { max-width: 32rem; padding: 2rem; text-align: center; }
        p { opacity: .7; }
        </style></head>
        <body><main><h1>\(escaped(title))</h1><p>\(escaped(message))</p></main></body></html>
        """
    }
}
