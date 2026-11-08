// Packaging vehicle only, never shipped. Xcode's Developer ID export and notarization work on
// app archives, not screensaver bundles, so scripts/package-release.sh archives this app with
// the savers embedded in Contents/PlugIns, lets Xcode sign (cloud-managed Developer ID) and
// notarize the lot, then lifts the notarized savers back out into the release zip.
import Foundation
print("Quiet Hours release carrier: not meant to be run.")
