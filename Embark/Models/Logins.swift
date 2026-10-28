import Foundation

/// A password saved in the Keychain. The password itself is read only when it's needed.
struct SavedLogin: Identifiable, Hashable {
    var host: String
    var username: String
    var profileID: Profile.ID
    var id: String { "\(profileID.uuidString)|\(host)|\(username)" }
}

/// A sign-in the page reported, waiting for the "Save password?" answer.
struct PendingLogin: Equatable {
    var host: String
    var username: String
    var password: String
    /// The account is saved already, with another password.
    var isUpdate: Bool
}

enum LoginHost {
    /// The site a password belongs to: the host without "www.".
    static func of(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The host part of an address typed or imported as text, which may lack a scheme.
    static func of(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let host = of(URL(string: trimmed)) { return host }
        return of(URL(string: "https://" + trimmed))
    }
}

/// What the page script reports, as JSON.
enum LoginMessage: Equatable {
    /// The page shows a password field.
    case form
    /// A password was typed and a sign-in started; it's saved once the form goes away or the
    /// page moves on.
    case candidate(username: String, password: String)
    /// The password field went away after a candidate, so the sign-in went through.
    case formGone

    static func parse(_ json: String) -> LoginMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let kind = object["kind"] as? String else { return nil }
        switch kind {
        case "form": return .form
        case "gone": return .formGone
        case "candidate":
            guard let password = object["password"] as? String, !password.isEmpty else { return nil }
            return .candidate(username: (object["username"] as? String) ?? "", password: password)
        default: return nil
        }
    }
}

/// The script Embark puts in each page's main frame to notice sign-ins and fill passwords.
/// It never sends a password anywhere but to Embark, and fills only when asked.
enum LoginScript {
    /// Chromium pages report through the console; Embark swallows lines with this prefix.
    static let consolePrefix = "\u{1}embark-login:"

    enum Channel { case console, webKit }

    static func source(for channel: Channel) -> String {
        let send = switch channel {
        case .console: "console.log(\(literal(consolePrefix)) + JSON.stringify(m))"
        case .webKit: "window.webkit.messageHandlers.embarkLogin.postMessage(JSON.stringify(m))"
        }
        return """
        (() => {
          if (window.__embarkLogins) return;
          window.__embarkLogins = true;
          const send = (m) => { try { \(send); } catch (e) {} };
          const visible = (el) => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
          const passwords = () => [...document.querySelectorAll('input[type=password]')].filter(visible);
          const textTypes = ['text', 'email', 'tel', ''];
          const usernameFor = (pw) => {
            const scope = pw.form || document;
            let found = null;
            for (const input of scope.querySelectorAll('input')) {
              if (input === pw) break;
              if (textTypes.includes(input.type) && visible(input)) found = input;
            }
            return found;
          };
          let reported = false, pending = false, last = '';
          const check = () => {
            const shown = passwords().length > 0;
            if (shown && !reported) { reported = true; send({ kind: 'form' }); }
            if (!shown && pending) { pending = false; send({ kind: 'gone' }); }
          };
          const capture = () => {
            const filled = passwords().filter((p) => p.value);
            if (!filled.length) return;
            const user = usernameFor(filled[0]);
            // In sign-up and change-password forms, the new password comes last.
            const entry = { kind: 'candidate', username: user ? user.value : '', password: filled[filled.length - 1].value };
            const key = entry.username + '\\u0000' + entry.password;
            pending = true;
            if (key === last) return;
            last = key;
            send(entry);
          };
          document.addEventListener('submit', capture, true);
          document.addEventListener('click', (e) => {
            if (e.target.closest && e.target.closest('button, input[type=submit], [role=button]')) capture();
          }, true);
          document.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && e.target.tagName === 'INPUT') capture();
          }, true);
          new MutationObserver(check).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'hidden'] });
          check();
          window.__embarkFill = (username, password) => {
            const pw = passwords()[0];
            if (!pw) return false;
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            const set = (el, value) => {
              el.focus();
              setter.call(el, value);
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            };
            const user = usernameFor(pw);
            if (user && username) set(user, username);
            set(pw, password);
            return true;
          };
        })();
        """
    }

    /// Calls the page script's fill function with the account.
    static func fillCall(username: String, password: String) -> String {
        "window.__embarkFill && window.__embarkFill(\(literal(username)), \(literal(password)));"
    }

    /// A JavaScript string literal for any text.
    static func literal(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        // [ "…" ] → "…"
        return String(array.dropFirst().dropLast())
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

/// Moving passwords to and from CSV, the format Apple's Passwords app, Chrome and most
/// password managers import and export.
enum PasswordCSV {
    struct Row: Equatable {
        var url: String
        var username: String
        var password: String
    }

    /// Reads rows by their column names (URL or url, Username, Password), so exports from
    /// Passwords, Safari, Chrome, Firefox, 1Password and Bitwarden all work.
    static func parse(_ text: String) -> [Row] {
        let records = records(text)
        guard let header = records.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return [] }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let url = column(["url", "website", "login_uri", "login url", "web site"]),
              let password = column(["password", "login_password"]) else { return [] }
        let username = column(["username", "user name", "login_username", "login", "email"])
        return records.dropFirst().compactMap { fields in
            guard fields.indices.contains(url), fields.indices.contains(password), !fields[password].isEmpty else { return nil }
            let user = username.flatMap { fields.indices.contains($0) ? fields[$0] : nil } ?? ""
            return Row(url: fields[url], username: user, password: fields[password])
        }
    }

    /// Writes Chrome's layout, which the Passwords app imports.
    static func export(_ rows: [(host: String, username: String, password: String)]) -> String {
        var lines = ["name,url,username,password,note"]
        for row in rows {
            lines.append([row.host, "https://\(row.host)/", row.username, row.password, ""].map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 4180: quoted fields can hold commas, quotes ("") and line breaks.
    private static func records(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": record.append(field); field = ""
                case "\n":
                    record.append(field); field = ""
                    if record != [""] { records.append(record) }
                    record = []
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}
