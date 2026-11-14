import CryptoKit
import Foundation
import Security
import Synchronization

/// URLSession delegate that trusts the Hue Bridge's own certificate, and only for the
/// saved bridge IP. Hue bridges use a self-signed (or Signify-signed) certificate that
/// iOS doesn't trust, so ordinary validation would fail. Instead:
/// - any other host gets the system's default handling (we never relax checks globally);
/// - in `.pairing` mode (only the Bridge screen's pairing client), the certificate the bridge
///   presents is accepted and remembered;
/// - in `.pinned` mode (every other client: app, widget, Siri), only a certificate with that
///   same SHA-256 hash is accepted. There is no "no pin, accept anything" outside pairing.
/// It also refuses HTTP redirects, so the key header is never forwarded to another host.
nonisolated final class BridgeTrust: NSObject, URLSessionTaskDelegate, Sendable {
    enum Mode: Sendable, Equatable {
        /// Pairing: accept the bridge's certificate and remember its hash.
        case pairing
        /// Paired: accept only the certificate with this SHA-256 hash.
        case pinned(Data)
    }

    let host: String
    let mode: Mode
    private let seen = Mutex<Data?>(nil)
    private let mismatch = Mutex(false)
    private let log: LogSink

    init(host: String, mode: Mode, log: LogSink) {
        self.host = host
        self.mode = mode
        self.log = log
    }

    /// The hash of the certificate the bridge presented (captured during pairing).
    var presentedHash: Data? { seen.withLock { $0 } }
    /// True once a certificate was refused for not matching the pinned one.
    var sawMismatch: Bool { mismatch.withLock { $0 } }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == host, let trust = space.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            log(.error, "Certificate: bridge sent no certificate")
            return (.cancelAuthenticationChallenge, nil)
        }
        let hash = Self.hash(of: leaf)
        seen.withLock { $0 = hash }
        switch Self.decide(mode, presented: hash) {
        case .accept:
            return (.useCredential, URLCredential(trust: trust))
        case .reject:
            mismatch.withLock { $0 = true }
            let pinned = if case .pinned(let p) = mode { p.prefix(4).hex } else { "-" }
            log(.error, "Certificate changed (\(hash.prefix(4).hex)… ≠ pinned \(pinned)…). Re-pair needed.")
            return (.cancelAuthenticationChallenge, nil)
        }
    }

    /// The bridge never redirects; refusing means the redirect reply itself comes back (and
    /// fails as an HTTP error) instead of the request, with its key, going somewhere else.
    /// (The completion-handler form: the async form crashes the Swift 6 compiler here.)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        log(.error, "Refused a redirect (\(response.statusCode)) to \(request.url?.host() ?? "?")")
        completionHandler(nil)
    }

    enum Decision: Equatable { case accept, reject }

    /// Pairing accepts the bridge's certificate; afterwards it must match the pin exactly.
    static func decide(_ mode: Mode, presented: Data) -> Decision {
        switch mode {
        case .pairing: .accept
        case .pinned(let pinned): !pinned.isEmpty && pinned == presented ? .accept : .reject
        }
    }

    static func hash(of certificate: SecCertificate) -> Data {
        Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }
}

extension Data {
    nonisolated var hex: String { map { String(format: "%02x", $0) }.joined() }
}
