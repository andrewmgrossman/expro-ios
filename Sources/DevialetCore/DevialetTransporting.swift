import Foundation

public protocol DevialetTransporting: AnyObject, Sendable {
    func startStatusListener(
        onPacket: @escaping @Sendable (Data, String?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws
    func stopStatusListener()
    func send(packet: Data, to ipAddress: String) async throws
}
