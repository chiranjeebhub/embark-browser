#!/usr/bin/env bash
# Writes the Sparkle appcast for one release to stdout. The release workflow uploads it next to
# the zip, and the app reads it from releases/latest/download/appcast.xml.
#
# Usage: scripts/make-appcast.sh VERSION BUILD ZIP_URL 'sparkle:edSignature="…" length="…"'
#   The last argument is what Sparkle's sign_update prints for the zip.
set -euo pipefail

VERSION="${1:?version}"
BUILD="${2:?build number}"
ZIP_URL="${3:?zip url}"
SIGNATURE="${4:?sign_update output}"
REPO_URL="https://github.com/chiranjeebhub/embark-browser"

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Embark</title>
    <link>$REPO_URL</link>
    <item>
      <title>Embark $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <description><![CDATA[<p>See what’s new in <a href="$REPO_URL/releases/tag/v$VERSION">the release notes</a>.</p>]]></description>
      <enclosure url="$ZIP_URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
