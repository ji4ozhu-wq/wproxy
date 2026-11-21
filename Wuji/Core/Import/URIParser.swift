import Foundation

/// Parses and encodes proxy share links (vmess://, vless://, trojan://, ss://).
/// Thin façade over `URIParserCore`; the implementation is owned by the data role.
final class URIParser {
    init() {}

    /// Parses one or more share links (newline separated or a base64 body).
    /// Throws `URIParseError` when no supported link could be read.
    func parse(_ text: String, groupID: String) throws -> [NodeProfile] {
        try URIParserCore.shared.parse(text, groupID: groupID)
    }

    /// Parses `text` and returns the rejected lines with their reasons, so import
    /// screens can report partial successes.
    func parseDetailed(_ text: String, groupID: String) -> URIParseReport {
        URIParserCore.shared.parseDetailed(text, groupID: groupID)
    }

    /// Parses exactly one share link (QR code, single clipboard item).
    func parseLink(_ link: String, groupID: String) throws -> NodeProfile {
        try URIParserCore.shared.parseLink(link, groupID: groupID)
    }

    /// Encodes a profile back to a share link for copy/share.
    func encode(_ profile: NodeProfile) -> String {
        URIParserCore.shared.encode(profile)
    }

    /// Extracts share links from a subscription body (base64 or plain list).
    func parseSubscriptionBody(_ body: String) -> [String] {
        URIParserCore.shared.parseSubscriptionBody(body)
    }

    /// Parameter names in `link` that the app cannot represent (ALPN, SS plugin...).
    func unsupportedParameters(in link: String) -> [String] {
        URIParserCore.shared.unsupportedParameters(in: link)
    }

    /// `true` when both profiles describe the same connection.
    func isDuplicate(_ profile: NodeProfile, of existing: NodeProfile) -> Bool {
        URIParserCore.isDuplicate(profile, of: existing)
    }

    /// `true` when `text` starts with a share link this app can import.
    func canParse(_ text: String) -> Bool {
        URIParserCore.shared.isSupportedLink(text)
    }
}
