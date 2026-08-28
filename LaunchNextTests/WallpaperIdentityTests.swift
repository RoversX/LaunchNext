import Foundation
import XCTest
import LaunchNextWallpaperCore

final class WallpaperIdentityTests: XCTestCase {
    private let displayA = "DISPLAY-A"
    private let displayB = "DISPLAY-B"

    func testDisplaySpecificDesktopChoiceDoesNotCrossDisplays() throws {
        let firstURL = URL(fileURLWithPath: "/Pictures/First.jpg")
        let secondURL = URL(fileURLWithPath: "/Pictures/Second.jpg")
        let store: [String: Any] = [
            "Displays": [
                displayA: entry(provider: imageProvider, configuration: imageConfiguration(firstURL)),
                displayB: entry(provider: imageProvider, configuration: imageConfiguration(secondURL))
            ]
        ]

        let first = try exactIdentity(WallpaperIdentityResolver.resolve(displayUUID: displayA, store: store))
        let second = try exactIdentity(WallpaperIdentityResolver.resolve(displayUUID: displayB, store: store))

        XCTAssertNotEqual(first.configurationDigest, second.configurationDigest)
        XCTAssertEqual(first.source, .image(firstURL.standardizedFileURL))
        XCTAssertEqual(second.source, .image(secondURL.standardizedFileURL))
    }

    func testRootDesktopWinsOverSpacesAndIdleIsIgnored() throws {
        let rootURL = URL(fileURLWithPath: "/Pictures/Current.jpg")
        let store: [String: Any] = [
            "Displays": [
                displayA: entry(
                    provider: imageProvider,
                    configuration: imageConfiguration(rootURL),
                    idleProvider: "com.apple.NeptuneOneExtension"
                )
            ],
            "Spaces": [
                "current": [
                    "Default": entry(
                        provider: aerialProvider,
                        configuration: ["assetID": "AERIAL-1"]
                    )
                ]
            ]
        ]

        let identity = try exactIdentity(
            WallpaperIdentityResolver.resolve(displayUUID: displayA, store: store)
        )

        XCTAssertEqual(identity.provider, imageProvider)
        XCTAssertEqual(identity.kind, .staticImage)
        XCTAssertEqual(identity.source, .image(rootURL.standardizedFileURL))
    }

    func testHistoricalSpacesAreIgnoredInFavorOfRootEntry() throws {
        // macOS never prunes the Spaces dictionary. A real machine accumulates
        // hundreds of stale entries that disagree with each other and with the
        // wallpaper actually in use, and no public API identifies the current
        // Space - so only the root Displays entry is authoritative.
        let currentAssetID = "CURRENT-AERIAL"
        var spaces: [String: Any] = [:]
        for index in 0..<700 {
            spaces["space-\(index)"] = [
                "Default": entry(
                    provider: aerialProvider,
                    configuration: ["assetID": "STALE-\(index % 12)"]
                )
            ]
        }
        let store: [String: Any] = [
            "Displays": [
                displayA: entry(
                    provider: aerialProvider,
                    configuration: ["assetID": currentAssetID]
                )
            ],
            "Spaces": spaces
        ]

        let identity = try exactIdentity(
            WallpaperIdentityResolver.resolve(displayUUID: displayA, store: store)
        )

        XCTAssertEqual(identity.source, .aerial(assetID: currentAssetID))
    }

    func testSpacesOnlyStoreResolvesToUnavailable() {
        let store: [String: Any] = [
            "Spaces": [
                "one": [
                    "Default": entry(provider: aerialProvider, configuration: ["assetID": "ONE"])
                ],
                "two": [
                    "Default": entry(provider: aerialProvider, configuration: ["assetID": "TWO"])
                ]
            ]
        ]

        // currentDesktopImageURL must be nil: a non-nil value would hit the
        // "no candidates -> fall back to the current desktop image" branch and
        // return .exact, which would defeat the point of this test.
        XCTAssertEqual(
            WallpaperIdentityResolver.resolve(
                displayUUID: displayA,
                store: store,
                currentDesktopImageURL: nil
            ),
            .unavailable
        )
    }

    func testIdleOnlyEntryIsUnavailable() {
        let store: [String: Any] = [
            "SystemDefault": [
                "Idle": [
                    "Content": [
                        "Choices": [choice(
                            provider: "com.apple.NeptuneOneExtension",
                            configuration: [:]
                        )]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(
            WallpaperIdentityResolver.resolve(displayUUID: displayA, store: store),
            .unavailable
        )
    }

    func testMultipleDifferentChoicesAreAmbiguous() {
        let store: [String: Any] = [
            "SystemDefault": entry(choices: [
                choice(provider: aerialProvider, configuration: ["assetID": "ONE"]),
                choice(provider: aerialProvider, configuration: ["assetID": "TWO"])
            ])
        ]

        XCTAssertEqual(
            WallpaperIdentityResolver.resolve(displayUUID: displayA, store: store),
            .ambiguous
        )
    }

    func testEncodedOptionsParticipateInIdentity() throws {
        let configuration = imageConfiguration(URL(fileURLWithPath: "/Pictures/Shared.jpg"))
        let firstStore: [String: Any] = [
            "SystemDefault": entry(
                provider: imageProvider,
                configuration: configuration,
                encodedOptions: plistData(["placement": "fill"])
            )
        ]
        let secondStore: [String: Any] = [
            "SystemDefault": entry(
                provider: imageProvider,
                configuration: configuration,
                encodedOptions: plistData(["placement": "fit"])
            )
        ]

        let first = try exactIdentity(
            WallpaperIdentityResolver.resolve(displayUUID: displayA, store: firstStore)
        )
        let second = try exactIdentity(
            WallpaperIdentityResolver.resolve(displayUUID: displayA, store: secondStore)
        )

        XCTAssertNotEqual(first.configurationDigest, second.configurationDigest)
    }

    func testDesktopImageURLIsExactWhenStoreIsUnavailable() throws {
        let url = URL(fileURLWithPath: "/Pictures/Current.jpg")
        let identity = try exactIdentity(
            WallpaperIdentityResolver.resolve(
                displayUUID: displayA,
                store: [:],
                currentDesktopImageURL: url
            )
        )

        XCTAssertEqual(identity.kind, .staticImage)
        XCTAssertEqual(identity.source, .image(url.standardizedFileURL))
    }

    func testDesktopImageURLOverridesAStaleStaticStoreEntry() throws {
        let staleURL = URL(fileURLWithPath: "/Pictures/Stale.jpg")
        let currentURL = URL(fileURLWithPath: "/Pictures/Current.jpg")
        let store: [String: Any] = [
            "SystemDefault": entry(
                provider: imageProvider,
                configuration: imageConfiguration(staleURL)
            )
        ]

        let identity = try exactIdentity(
            WallpaperIdentityResolver.resolve(
                displayUUID: displayA,
                store: store,
                currentDesktopImageURL: currentURL
            )
        )

        XCTAssertEqual(identity.source, .image(currentURL.standardizedFileURL))
    }

    func testRefreshPolicyReusesOnlyMatchingStaticContent() {
        XCTAssertEqual(
            WallpaperRefreshPolicy.windowShown(kind: .staticImage, hasMatchingContent: true),
            .reuse
        )
        XCTAssertEqual(
            WallpaperRefreshPolicy.windowShown(kind: .staticImage, hasMatchingContent: false),
            .capture
        )
        XCTAssertEqual(
            WallpaperRefreshPolicy.windowShown(kind: .animated, hasMatchingContent: true),
            .capture
        )
        XCTAssertEqual(
            WallpaperRefreshPolicy.windowShown(kind: nil, hasMatchingContent: true),
            .capture
        )
    }

    func testSnapshotLifecycleRejectsQueuedWriteAfterDisable() {
        let lifecycle = WallpaperSnapshotLifecycle()
        let queuedWrite = lifecycle.currentToken()
        let removal = lifecycle.transition(to: false)

        XCTAssertFalse(lifecycle.permitsPersistence(using: queuedWrite))
        XCTAssertTrue(lifecycle.permitsRemoval(using: removal))
    }

    func testSnapshotLifecycleReenableSupersedesPendingRemoval() {
        let lifecycle = WallpaperSnapshotLifecycle()
        let originalWrite = lifecycle.currentToken()
        let pendingRemoval = lifecycle.transition(to: false)
        let newWrite = lifecycle.transition(to: true)

        XCTAssertFalse(lifecycle.permitsPersistence(using: originalWrite))
        XCTAssertFalse(lifecycle.permitsRemoval(using: pendingRemoval))
        XCTAssertTrue(lifecycle.permitsPersistence(using: newWrite))
    }

    func testSnapshotLifecycleRepeatedStateDoesNotInvalidateCurrentWork() {
        let lifecycle = WallpaperSnapshotLifecycle(persistenceEnabled: false)
        let firstRemoval = lifecycle.currentToken()
        let repeatedRemoval = lifecycle.transition(to: false)

        XCTAssertEqual(firstRemoval, repeatedRemoval)
        XCTAssertTrue(lifecycle.permitsRemoval(using: repeatedRemoval))
    }

    private var imageProvider: String { "com.apple.wallpaper.choice.image" }
    private var aerialProvider: String { "com.apple.wallpaper.choice.aerials" }

    private func entry(
        provider: String,
        configuration: [String: Any],
        encodedOptions: Data = Data(),
        idleProvider: String? = nil
    ) -> [String: Any] {
        var result = entry(
            choices: [choice(provider: provider, configuration: configuration)],
            encodedOptions: encodedOptions
        )
        if let idleProvider {
            result["Idle"] = [
                "Content": [
                    "Choices": [choice(provider: idleProvider, configuration: [:])]
                ]
            ]
        }
        return result
    }

    private func entry(
        choices: [[String: Any]],
        encodedOptions: Data = Data()
    ) -> [String: Any] {
        [
            "Desktop": [
                "Content": [
                    "Choices": choices,
                    "EncodedOptionValues": encodedOptions
                ]
            ]
        ]
    }

    private func choice(
        provider: String,
        configuration: [String: Any]
    ) -> [String: Any] {
        [
            "Provider": provider,
            "Configuration": plistData(configuration),
            "Files": []
        ]
    }

    private func imageConfiguration(_ url: URL) -> [String: Any] {
        ["url": ["relative": url.absoluteString]]
    }

    private func plistData(_ value: Any) -> Data {
        try! PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        )
    }

    private func exactIdentity(
        _ resolution: WallpaperIdentityResolution,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WallpaperIdentity {
        guard case let .exact(identity) = resolution else {
            XCTFail("Expected an exact wallpaper identity, got \(resolution)", file: file, line: line)
            throw TestFailure.notExact
        }
        return identity
    }

    private enum TestFailure: Error {
        case notExact
    }
}
