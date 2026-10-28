import Foundation
import Testing

/// Page messages, the fill call, hosts and CSV import/export for saved passwords.
struct LoginTests {
    @Test func messagesParse() {
        #expect(LoginMessage.parse(#"{"kind":"form"}"#) == .form)
        #expect(LoginMessage.parse(#"{"kind":"gone"}"#) == .formGone)
        #expect(LoginMessage.parse(#"{"kind":"candidate","username":"me@x.com","password":"pw"}"#)
                == .candidate(username: "me@x.com", password: "pw"))
        #expect(LoginMessage.parse(#"{"kind":"candidate","username":"me","password":""}"#) == nil)
        #expect(LoginMessage.parse("nope") == nil)
    }

    @Test func fillCallEscapesEverything() {
        let call = LoginScript.fillCall(username: "a\"b", password: "x'</script>\\\n\u{2028}")
        #expect(call.contains(#""a\"b""#))
        #expect(!call.contains("\n"))
        #expect(!call.contains("\u{2028}"))
        #expect(call.hasPrefix("window.__embarkFill && window.__embarkFill("))
    }

    @Test func hostsDropWWW() {
        #expect(LoginHost.of(URL(string: "https://www.github.com/login")) == "github.com")
        #expect(LoginHost.of(URL(string: "https://accounts.google.com/x")) == "accounts.google.com")
        #expect(LoginHost.of(URL(string: "file:///tmp/a.html")) == nil)
        #expect(LoginHost.of("netflix.com") == "netflix.com")
    }

    @Test func importsPasswordsAppCSV() {
        let csv = "Title,URL,Username,Password,Notes,OTPAuth\r\ngithub.com (me),https://github.com/,me,\"p,w\"\"1\",,\r\nNo password,https://a.com,,,,\r\n"
        #expect(PasswordCSV.parse(csv) == [PasswordCSV.Row(url: "https://github.com/", username: "me", password: "p,w\"1")])
    }

    @Test func importsChromeCSVWithLineBreaksInQuotes() {
        let csv = "name,url,username,password,note\nx,https://x.com,u,\"multi\nline\",n\n"
        #expect(PasswordCSV.parse(csv) == [PasswordCSV.Row(url: "https://x.com", username: "u", password: "multi\nline")])
    }

    @Test func exportRoundTrips() {
        let text = PasswordCSV.export([(host: "x.com", username: "a,b", password: "q\"uote")])
        #expect(PasswordCSV.parse(text) == [PasswordCSV.Row(url: "https://x.com/", username: "a,b", password: "q\"uote")])
    }
}
