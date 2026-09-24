import AppKit
import XCTest

@MainActor
final class TalosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// XCUITest leaves the app under test running (and frontmost) when a
    /// test ends, so local runs would strand a fixture-workspace browser on
    /// the developer's screen. Every test launches its own instance, so
    /// tearing the app down between tests costs nothing.
    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    static let splitFixturePageHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <title>Split Fixture</title>
        <script>document.title = location.pathname.slice(1)</script>
      </head>
      <body><h1>Split pane fixture</h1></body>
    </html>
    """

    /// A solid #00ff00 page so pixel sampling has an unmistakable baseline:
    /// the pane center proves web content rendered, and any chrome drawn
    /// over the page must move a sampled channel away from pure green.
    static let pixelProbeFixturePageHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <script>document.title = location.pathname.slice(1)</script>
        <style>html, body { margin: 0; height: 100%; background: #00ff00; }</style>
      </head>
      <body></body>
    </html>
    """

    /// Hosted web-authentication fixture: the path picks the provider
    /// behavior — an immediate matching-scheme callback, a non-matching
    /// scheme, or an idle page that waits to be dismissed.
    static let webAuthFixturePageHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <script>
          addEventListener("load", () => {
            if (location.pathname === "/auth-success") {
              location.href = "talos-e2e://auth?code=ok";
            } else if (location.pathname === "/auth-wrong") {
              location.href = "wrong-scheme://auth?code=bad";
            }
          });
        </script>
      </head>
      <body><h1>Web auth fixture</h1></body>
    </html>
    """

    /// A job application: three personal fields the snapshot marks sensitive
    /// (their autocomplete tokens), plus a submit button that is sensitive
    /// because it sends them. The status line reports how many fields are
    /// filled — a count, not labels, so the fixture agent can pick the next
    /// field without depending on how the snapshot happens to label it.
    static let pageHTMLFixtures: [String: String] = [
        "split-view": splitFixturePageHTML,
        "tab-switcher-previews": splitFixturePageHTML,
        "split-view-spaces": splitFixturePageHTML,
        "split-view-pixels": pixelProbeFixturePageHTML,
        "web-auth": webAuthFixturePageHTML,
        "download-page": """
        <!doctype html>
        <meta charset="utf-8">
        <title>Download Fixture</title>
        <a href="data:application/octet-stream;base64,Q2FuZG9hIGUyZSBkb3dubG9hZCBmaXh0dXJl"
           download="talos-e2e-download.bin"
           style="position:fixed;inset:0;font-size:40px">Download</a>
        """,
        // Retitles itself on a timer: each new title re-publishes the
        // window's command state, which makes SwiftUI rebuild the menu bar —
        // the churn that used to wipe the History menu's rows mid-open.
        "history-menu-churn": """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <script>document.title = location.pathname.slice(1)</script>
          </head>
          <body>
            <script>
              let tick = 0;
              setInterval(() => { document.title = "churn-" + (++tick); }, 400);
            </script>
          </body>
        </html>
        """,
        "popup-open": """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <script>document.title = location.pathname.slice(1)</script>
          </head>
          <body>
            <script>
              document.addEventListener("click", () => {
                window.open("https://fixture.talos.test/popup-child");
              });
            </script>
          </body>
        </html>
        """,
        // A viewport-filling real anchor, so a modifier-held coordinate click
        // anywhere in the web area activates an actual link navigation.
        "link-click": """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <script>document.title = location.pathname.slice(1)</script>
          </head>
          <body>
            <a href="https://fixture.talos.test/link-target"
               style="position:fixed;inset:0;font-size:40px">Open</a>
          </body>
        </html>
        """,
        // A sign-in redirect whose script never finishes the handshake: the
        // page has an OAuth response in its URL and nothing to show.
        "signin-dead-end": """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"></head>
          <body></body>
        </html>
        """,
        // The same shape of URL, but the site did land somewhere real.
        "signin-landed": """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"><title>Signed In</title></head>
          <body><h1>You are signed in</h1></body>
        </html>
        """,
        "reader-article": """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="author" content="Fixture Author">
            <script>document.title = location.pathname.slice(1)</script>
          </head>
          <body>
            <nav><a href="https://fixture.talos.test/elsewhere">Fixture Nav Link</a></nav>
            <article>
              <h1>Reader Fixture Article</h1>
              <p>Reader fixture marker sentence.</p>
              <p>The availability probe needs sustained paragraph text before it will call a page an article, so this fixture carries several sentences of steady filler that read like the body of a feature story and push the character count well past the threshold.</p>
              <p>A second long paragraph keeps the scoring honest by adding more genuine sentence text, the kind that live articles have in abundance and navigation pages never do, which is exactly the distinction the reader probe is built to draw.</p>
              <p>The third paragraph exists so that trimming any single block in extraction cannot drop the fixture below the availability threshold, keeping this test focused on the reader flow instead of the scoring boundary.</p>
            </article>
          </body>
        </html>
        """,
        "history": """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"><title>Talos History Fixture</title></head>
          <body><h1>Talos History Fixture</h1><p>Representative browsing history.</p></body>
        </html>
        """,
    ]

}
