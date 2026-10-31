import Foundation

/// What a page is playing, as its media script reports it. Chromium (CEF) tells embedders
/// nothing about sound, so both engines learn it from the page's audio and video elements.
struct MediaState: Equatable {
    var isPlaying: Bool
    var hasVideo: Bool
    /// The Media Session title, or the page title.
    var title: String
    var artist: String
    var artwork: URL?
    /// The page handles next and previous track (playlists, music sites).
    var canGoNext: Bool
    var canGoPrevious: Bool
    var canPictureInPicture: Bool
}

/// A media script message: nothing is playing or paused part way, or the media's state.
enum MediaMessage: Equatable {
    case idle
    case media(MediaState)

    static func parse(_ json: String) -> MediaMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let active = object["active"] as? Bool else { return nil }
        guard active else { return .idle }
        let artwork = (object["artwork"] as? String).flatMap(URL.init(string:))
            .flatMap { ["https", "http", "data"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        return .media(MediaState(isPlaying: object["playing"] as? Bool ?? false,
                                 hasVideo: object["video"] as? Bool ?? false,
                                 title: object["title"] as? String ?? "",
                                 artist: object["artist"] as? String ?? "",
                                 artwork: artwork,
                                 canGoNext: object["next"] as? Bool ?? false,
                                 canGoPrevious: object["previous"] as? Bool ?? false,
                                 canPictureInPicture: object["pip"] as? Bool ?? false))
    }
}

/// What the tab's speaker button and the mini player ask the page to do.
enum MediaCommand: String {
    case play, pause, toggle
    case next = "nexttrack"
    case previous = "previoustrack"
    /// Mutes the page's media elements. Chromium mutes the whole tab instead.
    case mute, unmute
    case pictureInPicture = "pip"
}

/// The script Embark puts in each page's main frame to see what plays with sound and to
/// control it from the sidebar. Muted autoplay videos don't count.
enum MediaScript {
    /// Chromium pages report through the console; Embark swallows lines with this prefix.
    static let consolePrefix = "\u{1}embark-media:"

    static func source(for channel: LoginScript.Channel) -> String {
        let send = switch channel {
        case .console: "console.log(\(LoginScript.literal(consolePrefix)) + m)"
        case .webKit: "window.webkit.messageHandlers.embarkMedia.postMessage(m)"
        }
        return """
        (() => {
          if (window.__embarkMedia) return;
          const send = (m) => { try { \(send); } catch (e) {} };
          const handlers = {};
          const extra = new Set();
          const events = ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange', 'loadedmetadata'];
          let muted = false, last = null, sent = '', timer = 0;
          const session = navigator.mediaSession;
          const isMedia = (e) => e instanceof HTMLMediaElement;
          const audible = (e) => (!e.muted || e.__embarkMuted) && e.volume > 0;
          const all = () => {
            const list = [...document.querySelectorAll('video, audio')];
            extra.forEach((e) => { if (!e.isConnected) list.push(e); });
            return list;
          };
          const alive = (e) => e && !e.ended && e.currentSrc && (e.isConnected || extra.has(e));
          const muteElement = (e) => { if (!e.muted) { e.muted = true; e.__embarkMuted = true; } };
          const report = () => {
            timer = 0;
            const playing = all().filter((e) => !e.paused && !e.ended && audible(e));
            const e = playing.includes(last) ? last : (playing[0] || (alive(last) ? last : null));
            last = e;
            let m = { active: false };
            if (e) {
              const meta = session && session.metadata;
              const art = meta && meta.artwork && meta.artwork.length ? meta.artwork[meta.artwork.length - 1].src : '';
              let artwork = '';
              try { artwork = art ? new URL(art, location.href).href : ''; } catch (err) {}
              const video = e.tagName === 'VIDEO' && e.videoWidth > 0;
              m = {
                active: true, playing: playing.length > 0, video,
                title: (meta && meta.title) || document.title || '', artist: (meta && meta.artist) || '', artwork,
                next: !!handlers.nexttrack, previous: !!handlers.previoustrack,
                pip: video && (!!document.pictureInPictureEnabled || typeof e.webkitSetPresentationMode === 'function'),
              };
            }
            const json = JSON.stringify(m);
            if (json !== sent) { sent = json; send(json); }
          };
          const schedule = () => { if (!timer) timer = setTimeout(report, 60); };
          const onEvent = (ev) => {
            const e = ev.target;
            if (!isMedia(e)) return;
            if (ev.type === 'play' && muted) muteElement(e);
            if ((ev.type === 'play' || ev.type === 'playing') && audible(e)) last = e;
            if ((ev.type === 'ended' || ev.type === 'emptied') && !e.isConnected) extra.delete(e);
            schedule();
          };
          events.forEach((t) => document.addEventListener(t, onEvent, true));
          // Audio made with `new Audio()` never joins the document, so its events don't reach it.
          const watch = (e) => {
            if (e.isConnected || extra.has(e)) return;
            extra.add(e);
            events.forEach((t) => e.addEventListener(t, onEvent));
          };
          const proto = HTMLMediaElement.prototype, originalPlay = proto.play;
          proto.play = function () { watch(this); if (muted) muteElement(this); return originalPlay.apply(this, arguments); };
          if (session && session.setActionHandler) {
            const set = session.setActionHandler.bind(session);
            session.setActionHandler = (action, handler) => { set(action, handler); handlers[action] = handler; schedule(); };
          }
          window.__embarkMedia = (cmd) => {
            const e = alive(last) ? last : null;
            if (cmd === 'mute') { muted = true; all().forEach(muteElement); }
            else if (cmd === 'unmute') {
              muted = false;
              all().forEach((x) => { if (x.__embarkMuted) { x.muted = false; x.__embarkMuted = false; } });
            } else if (cmd === 'play' || cmd === 'pause' || cmd === 'toggle') {
              const play = cmd === 'play' || (cmd === 'toggle' && (!e || e.paused));
              const action = play ? 'play' : 'pause';
              if (e) { if (play) { const p = e.play(); if (p) p.catch(() => {}); } else e.pause(); }
              else if (handlers[action]) handlers[action]({ action });
            } else if (cmd === 'nexttrack' || cmd === 'previoustrack') {
              if (handlers[cmd]) handlers[cmd]({ action: cmd });
            } else if (cmd === 'pip' && e) {
              const fallback = () => { if (e.webkitSetPresentationMode) e.webkitSetPresentationMode('picture-in-picture'); };
              if (document.pictureInPictureElement) document.exitPictureInPicture();
              else if (e.requestPictureInPicture) e.requestPictureInPicture().catch(fallback);
              else fallback();
            }
            schedule();
          };
          // Media Session titles change between tracks without an event.
          setInterval(() => { if (last) report(); }, 2000);
          report();
        })();
        """
    }

    static func call(_ command: MediaCommand) -> String {
        "window.__embarkMedia && window.__embarkMedia(\(LoginScript.literal(command.rawValue)));"
    }
}
