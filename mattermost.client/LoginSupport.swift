//
//  LoginSupport.swift
//  mattermost.client
//
//  Pure helpers for server login: SSO provider discovery, MFA detection and
//  session-cookie/token extraction. Kept separate so the login UI stays thin.
//

import Foundation

enum LoginSupport {
    struct SSOProvider: Equatable {
        let id: String
        let title: String
        let path: String
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
