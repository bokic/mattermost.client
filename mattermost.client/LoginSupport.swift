//
//  LoginSupport.swift
//  mattermost.client
//
//  Pure helpers for server login: SSO provider discovery, MFA detection,
//  session-cookie/token extraction and email-domain server discovery.
//

import Foundation

enum LoginSupport {
    struct SSOProvider: Equatable {
        let id: String
        let title: String
        let path: String
    }

    struct DiscoveredServer: Equatable {
        let host: String
        let port: UInt16
        let url: URL
        let siteName: String?
    }

    /// Common consumer webmail providers where domain-based Mattermost server discovery does not apply.
    static let publicWebmailDomains: Set<String> = [
        "gmail.com", "googlemail.com", "yahoo.com", "ymail.com",
        "hotmail.com", "outlook.com", "live.com", "msn.com",
        "icloud.com", "me.com", "mac.com", "aol.com",
        "proton.me", "protonmail.com", "zoho.com", "mail.com",
        "gmx.com", "gmx.net", "fastmail.com", "tutanota.com"
    ]

    static func isPublicWebmail(domain: String) -> Bool {
        publicWebmailDomains.contains(domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func extractDomain(fromEmail email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.lastIndex(of: "@") else { return nil }
        let userPart = trimmed[..<atIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let domainPart = String(trimmed[trimmed.index(after: atIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !userPart.isEmpty, !domainPart.isEmpty, domainPart.contains(".") else { return nil }
        guard !domainPart.hasPrefix("."), !domainPart.hasSuffix(".") else { return nil }
        return domainPart
    }

    static func candidateServerURLs(forDomain domain: String) -> [URL] {
        let cleanDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDomain.isEmpty else { return [] }

        var hostCandidates: [String] = []
        if !cleanDomain.hasPrefix("chat.") && !cleanDomain.hasPrefix("mattermost.") && !cleanDomain.hasPrefix("mm.") {
            hostCandidates.append("chat.\(cleanDomain)")
            hostCandidates.append("mattermost.\(cleanDomain)")
            hostCandidates.append("mm.\(cleanDomain)")
        }
        hostCandidates.append(cleanDomain)

        var urls: [URL] = []
        for host in hostCandidates {
            if let url = URL(string: "https://\(host)") {
                urls.append(url)
            }
        }
        if let subpathURL = URL(string: "https://\(cleanDomain)/mattermost") {
            urls.append(subpathURL)
        }
        return urls
    }

    static func verifyMattermostServer(at baseURL: URL, session: URLSession = .shared) async -> DiscoveredServer? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = basePath.isEmpty ? "" : "/\(basePath)"
        components.path = "\(prefix)/api/v4/system/ping"

        guard let pingURL = components.url else { return nil }
        var request = URLRequest(url: pingURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["status"] as? String)?.uppercased() == "OK" else {
                return nil
            }

            var siteName: String? = nil
            components.path = "\(prefix)/api/v4/config/client"
            components.queryItems = [URLQueryItem(name: "format", value: "old")]
            if let configURL = components.url {
                var configReq = URLRequest(url: configURL)
                configReq.timeoutInterval = 2.0
                configReq.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (cfgData, cfgResp) = try? await session.data(for: configReq),
                   let cfgHttp = cfgResp as? HTTPURLResponse, cfgHttp.statusCode == 200,
                   let cfgJson = try? JSONSerialization.jsonObject(with: cfgData) as? [String: Any] {
                    siteName = cfgJson["SiteName"] as? String
                }
            }

            let host = baseURL.host ?? ""
            let port = UInt16(baseURL.port ?? (baseURL.scheme == "http" ? 80 : 443))
            return DiscoveredServer(host: host, port: port, url: baseURL, siteName: siteName)
        } catch {
            return nil
        }
    }

    static func discoverServer(forEmail email: String, session: URLSession = .shared) async -> DiscoveredServer? {
        guard let domain = extractDomain(fromEmail: email) else { return nil }
        return await discoverServer(forDomain: domain, session: session)
    }

    static func discoverServer(forDomain domain: String, session: URLSession = .shared) async -> DiscoveredServer? {
        if isPublicWebmail(domain: domain) { return nil }
        let candidates = candidateServerURLs(forDomain: domain)
        guard !candidates.isEmpty else { return nil }

        return await withTaskGroup(of: (Int, DiscoveredServer?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let result = await verifyMattermostServer(at: candidate, session: session)
                    return (index, result)
                }
            }
            var matches: [(Int, DiscoveredServer)] = []
            for await (index, server) in group {
                if let server = server {
                    matches.append((index, server))
                }
            }
            matches.sort { $0.0 < $1.0 }
            return matches.first?.1
        }
    }

    static func providers(fromClientConfig data: Data) -> [SSOProvider] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        func enabledSettings(_ key: String) -> [String: Any]? {
            guard let settings = json[key] as? [String: Any] else { return nil }
            if let enabled = settings["Enable"] as? Bool, enabled { return settings }
            if let enabled = settings["Enable"] as? String,
               enabled.caseInsensitiveCompare("true") == .orderedSame {
                return settings
            }
            return nil
        }

        var providers: [SSOProvider] = []
        if enabledSettings("SamlSettings") != nil {
            providers.append(SSOProvider(id: "saml", title: "SAML SSO", path: "/saml/login"))
        }
        if enabledSettings("GitLabSettings") != nil {
            providers.append(SSOProvider(id: "gitlab", title: "GitLab", path: "/oauth/gitlab/login"))
        }
        if enabledSettings("GoogleSettings") != nil {
            providers.append(SSOProvider(id: "google", title: "Google", path: "/oauth/google/login"))
        }
        if enabledSettings("Office365Settings") != nil {
            providers.append(
                SSOProvider(id: "office365", title: "Microsoft 365", path: "/oauth/office365/login")
            )
        }
        if let settings = enabledSettings("OpenIdConnectSettings") {
            let title = (settings["ButtonText"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "OpenID Connect"
            providers.append(
                SSOProvider(id: "openid", title: title, path: "/oauth/openid/login")
            )
        }
        return providers
    }

    static func isMFARequired(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("mfa")
            || text.contains("multi-factor")
            || text.contains("multi factor")
            || text.contains("authenticator")
    }

    static func token(fromRedirectURL url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let names = ["token", "MMAUTHTOKEN", "access_token", "mfa_token"]
        for name in names {
            if let value = components.queryItems?.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })?.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func token(from cookies: [HTTPCookie]) -> String? {
        let names = ["MMAUTHTOKEN", "MMTOKEN"]
        for cookie in cookies {
            if names.contains(where: { $0.caseInsensitiveCompare(cookie.name) == .orderedSame }),
               !cookie.value.isEmpty {
                return cookie.value
            }
        }
        return nil
    }
}
