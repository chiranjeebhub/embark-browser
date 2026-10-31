import Foundation
import Testing

/// Media script messages and calls, for the tab speaker and the mini player.
struct MediaTests {
    @Test func idleAndBadMessages() {
        #expect(MediaMessage.parse(#"{"active":false}"#) == .idle)
        #expect(MediaMessage.parse(#"{"unsupported":true}"#) == .unsupportedCodec)
        #expect(MediaMessage.parse("nope") == nil)
        #expect(MediaMessage.parse(#"{"playing":true}"#) == nil)
    }

    @Test func mediaMessageParses() {
        let json = #"{"active":true,"playing":true,"video":true,"title":"Song","artist":"Band","#
            + #""artwork":"https://i.ytimg.com/a.jpg","next":true,"previous":false,"pip":true}"#
        #expect(MediaMessage.parse(json) == .media(MediaState(
            isPlaying: true, hasVideo: true, title: "Song", artist: "Band",
            artwork: URL(string: "https://i.ytimg.com/a.jpg"), canGoNext: true, canGoPrevious: false,
            canPictureInPicture: true)))
    }

    @Test func artworkOnlyFromTheWeb() {
        guard case .media(let state) = MediaMessage.parse(#"{"active":true,"artwork":"file:///etc/passwd"}"#) else {
            Issue.record("not parsed")
            return
        }
        #expect(state.artwork == nil)
        #expect(state.isPlaying == false)
    }

    @Test func commandCalls() {
        #expect(MediaScript.call(.next) == #"window.__embarkMedia && window.__embarkMedia("nexttrack");"#)
        #expect(MediaScript.call(.pictureInPicture).contains(#""pip""#))
    }

    @Test func scriptsUseTheirChannel() {
        #expect(MediaScript.source(for: .webKit).contains("messageHandlers.embarkMedia"))
        #expect(MediaScript.source(for: .console).contains("console.log("))
    }
}
