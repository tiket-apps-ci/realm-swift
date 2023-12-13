// swift-tools-version:5.9

import PackageDescription
import Foundation

let coreVersion = Version("13.23.1")
let cocoaVersion = Version("10.44.0")

let cxxSettings: [CXXSetting] = [
    .headerSearchPath("."),
    .headerSearchPath("include"),
    .define("REALM_SPM", to: "1"),
    .define("REALM_ENABLE_SYNC", to: "1"),
    .define("REALM_COCOA_VERSION", to: "@\"\(cocoaVersion)\""),
    .define("REALM_VERSION", to: "\"\(coreVersion)\""),
    .define("REALM_IOPLATFORMUUID", to: "@\"\(runCommand())\""),

    .define("REALM_DEBUG", .when(configuration: .debug)),
    .define("REALM_NO_CONFIG"),
    .define("REALM_INSTALL_LIBEXECDIR", to: ""),
    .define("REALM_ENABLE_ASSERTIONS", to: "1"),
    .define("REALM_ENABLE_ENCRYPTION", to: "1"),

    .define("REALM_VERSION_MAJOR", to: String(coreVersion.major)),
    .define("REALM_VERSION_MINOR", to: String(coreVersion.minor)),
    .define("REALM_VERSION_PATCH", to: String(coreVersion.patch)),
    .define("REALM_VERSION_EXTRA", to: "\"\(coreVersion.prereleaseIdentifiers.first ?? "")\""),
    .define("REALM_VERSION_STRING", to: "\"\(coreVersion)\""),
]
let testCxxSettings: [CXXSetting] = cxxSettings + [
    // Command-line `swift build` resolves header search paths
    // relative to the package root, while Xcode resolves them
    // relative to the target root, so we need both.
    .headerSearchPath("Realm"),
    .headerSearchPath(".."),
]

// SPM requires all targets to explicitly include or exclude every file, which
// gets very awkward when we have four targets building from a single directory
let objectServerTestSources = [
    "Object-Server-Tests-Bridging-Header.h",
    "ObjectServerTests-Info.plist",
    "RLMAsymmetricSyncServerTests.mm",
    "RLMBSONTests.mm",
    "RLMCollectionSyncTests.mm",
    "RLMFlexibleSyncServerTests.mm",
    "RLMObjectServerPartitionTests.mm",
    "RLMObjectServerTests.mm",
    "RLMServerTestObjects.m",
    "RLMSyncTestCase.h",
    "RLMSyncTestCase.mm",
    "RLMUser+ObjectServerTests.h",
    "RLMUser+ObjectServerTests.mm",
    "RLMWatchTestUtility.h",
    "RLMWatchTestUtility.m",
    "EventTests.swift",
    "RealmServer.swift",
    "SwiftAsymmetricSyncServerTests.swift",
    "SwiftCollectionSyncTests.swift",
    "SwiftFlexibleSyncServerTests.swift",
    "SwiftMongoClientTests.swift",
    "SwiftObjectServerPartitionTests.swift",
    "SwiftObjectServerTests.swift",
    "SwiftServerObjects.swift",
    "SwiftSyncTestCase.swift",
    "SwiftUIServerTests.swift",
    "TimeoutProxyServer.swift",
    "WatchTestUtility.swift",
    "certificates",
    "config_overrides.json",
    "include",
    "setup_baas.rb",
]

func objectServerTestSupportTarget(name: String, dependencies: [Target.Dependency], sources: [String]) -> Target {
    .target(
        name: name,
        dependencies: dependencies,
        path: "Realm/ObjectServerTests",
        exclude: objectServerTestSources.filter { !sources.contains($0) },
        sources: sources,
        cxxSettings: testCxxSettings
    )
}

func objectServerTestTarget(name: String, sources: [String]) -> Target {
    .testTarget(
        name: name,
        dependencies: ["RealmSwift", "RealmTestSupport", "RealmSyncTestSupport", "RealmSwiftSyncTestSupport", "SetupBaas"],
        path: "Realm/ObjectServerTests",
        exclude: objectServerTestSources.filter { !sources.contains($0) },
        sources: sources,
        resources: [.copy("Realm/ObjectServerTests/Resources")],
        cxxSettings: testCxxSettings
//        plugins: [.plugin(name: "BaasPlugin")]
    )
}

func runCommand() -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.launchPath = "/usr/sbin/ioreg"
    task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
    task.standardInput = nil
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    let range = NSRange(output.startIndex..., in: output)
    guard let regex = try? NSRegularExpression(pattern: ".*\\\"IOPlatformUUID\\\"\\s=\\s\\\"(.+)\\\"", options: .caseInsensitive),
          let firstMatch = regex.matches(in: output, range: range).first else {
        return ""
    }

    let matches = (0..<firstMatch.numberOfRanges).compactMap { ind -> String? in
        let matchRange = firstMatch.range(at: ind)
        if matchRange != range,
           let substringRange = Range(matchRange, in: output) {
            let capture = String(output[substringRange])
            return capture
        }
        return nil
    }
    return matches.last ?? ""
}
//var pluginWorkDirectory = CommandLine.arguments[1]
//var isDirectory = ObjCBool(false)
//if FileManager.default.fileExists(atPath: pluginWorkDirectory,
//                                  isDirectory: &isDirectory), !isDirectory.boolValue {
//    pluginWorkDirectory = FileManager.default.currentDirectoryPath
//}
//var BASE_DIR = pluginWorkDirectory
// var BUILD_DIR = "\(BASE_DIR)/.baas"
// var BIN_DIR = "\(BUILD_DIR)/bin"
// var LIB_DIR = "\(BUILD_DIR)/lib"
// var PID_FILE = "\(BUILD_DIR)/pid.txt"
//
// var MONGO_EXE = "'\(BIN_DIR)'/mongo"
// var MONGOD_EXE = "'\(BIN_DIR)'/mongod"
//
// var DEPENDENCIES = try! String(data: Data(contentsOf: URL(filePath: "\(BASE_DIR)/dependencies.list")), encoding: .utf8)!
//    .split(separator: "\n")
//    .map {
//        $0.split(separator: "=").map(String.init)
//    }.reduce(into: [String: String](), {
//        $0[$1[0]] = $1[1]
//    })
//
// var MONGODB_VERSION = "5.0.6"
// var GO_VERSION = "1.19.5"
// var NODE_VERSION = "16.13.1"
// var STITCH_VERSION = DEPENDENCIES["STITCH_VERSION"]
//
// var MONGODB_URL = "https://fastdl.mongodb.org/osx/mongodb-macos-x86_64-\(MONGODB_VERSION).tgz"
//let TRANSPILER_TARGET = "node16-macos"
//let SERVER_STITCH_LIB_URL = "https://s3.amazonaws.com/stitch-artifacts/stitch-support/stitch-support-macos-debug-4.3.2-721-ge791a2e-patch-5e2a6ad2a4cf473ae2e67b09.tgz"
//let STITCH_SUPPORT_URL="https://static.realm.io/downloads/swift/stitch-support.tar.xz"
//let MONGO_DIR="\(BUILD_DIR)/mongodb-macos-x86_64-#{MONGODB_VERSION}"
//
//if !FileManager.default.fileExists(atPath: BUILD_DIR) {
//    try FileManager.default.createDirectory(atPath: BUILD_DIR,
//                                            withIntermediateDirectories: false)
//    try FileManager.default.createDirectory(atPath: BIN_DIR,
//                                            withIntermediateDirectories: false)
//    try FileManager.default.createDirectory(atPath: LIB_DIR,
//                                            withIntermediateDirectories: false)
//}
//let (url, response) = try await URLSession(configuration: .default)
//    .download(from: URL(string: MONGODB_URL)!)

let package = Package(
    name: "Realm",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v4)
    ],
    products: [
        .library(
            name: "Realm",
            targets: ["Realm"]),
        .library(
            name: "RealmSwift",
            targets: ["Realm", "RealmSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/realm/realm-core.git", exact: coreVersion)
    ],
    targets: [
      .target(
            name: "Realm",
            dependencies: [.product(name: "RealmCore", package: "realm-core")],
            path: ".",
            exclude: [
                "CHANGELOG.md",
                "CONTRIBUTING.md",
                "Carthage",
                "Configuration",
                "Jenkinsfile.releasability",
                "LICENSE",
                "Package.swift",
                "README.md",
                "Realm.podspec",
                "Realm.xcodeproj",
                "Realm/ObjectServerTests",
                "Realm/Realm-Info.plist",
                "Realm/Swift/RLMSupport.swift",
                "Realm/TestUtils",
                "Realm/Tests",
                "RealmSwift",
                "RealmSwift.podspec",
                "SUPPORT.md",
                "build.sh",
                "ci_scripts/ci_post_clone.sh",
                "contrib",
                "dependencies.list",
                "docs",
                "examples",
                "include",
                "logo.png",
                "plugin",
                "scripts",
            ],
            sources: [
                "Realm/RLMAccessor.mm",
                "Realm/RLMAnalytics.mm",
                "Realm/RLMArray.mm",
                "Realm/RLMAsymmetricObject.mm",
                "Realm/RLMAsyncTask.mm",
                "Realm/RLMClassInfo.mm",
                "Realm/RLMCollection.mm",
                "Realm/RLMConstants.m",
                "Realm/RLMDecimal128.mm",
                "Realm/RLMDictionary.mm",
                "Realm/RLMEmbeddedObject.mm",
                "Realm/RLMError.mm",
                "Realm/RLMEvent.mm",
                "Realm/RLMLogger.mm",
                "Realm/RLMManagedArray.mm",
                "Realm/RLMManagedDictionary.mm",
                "Realm/RLMManagedSet.mm",
                "Realm/RLMMigration.mm",
                "Realm/RLMObject.mm",
                "Realm/RLMObjectBase.mm",
                "Realm/RLMObjectId.mm",
                "Realm/RLMObjectSchema.mm",
                "Realm/RLMObjectStore.mm",
                "Realm/RLMObservation.mm",
                "Realm/RLMPredicateUtil.mm",
                "Realm/RLMProperty.mm",
                "Realm/RLMQueryUtil.mm",
                "Realm/RLMRealm.mm",
                "Realm/RLMRealmConfiguration.mm",
                "Realm/RLMRealmUtil.mm",
                "Realm/RLMResults.mm",
                "Realm/RLMScheduler.mm",
                "Realm/RLMSchema.mm",
                "Realm/RLMSectionedResults.mm",
                "Realm/RLMSet.mm",
                "Realm/RLMSwiftCollectionBase.mm",
                "Realm/RLMSwiftSupport.m",
                "Realm/RLMSwiftValueStorage.mm",
                "Realm/RLMThreadSafeReference.mm",
                "Realm/RLMUUID.mm",
                "Realm/RLMUpdateChecker.mm",
                "Realm/RLMUtil.mm",
                "Realm/RLMValue.mm",

                // Sync source files
                "Realm/NSError+RLMSync.m",
                "Realm/RLMApp.mm",
                "Realm/RLMAPIKeyAuth.mm",
                "Realm/RLMBSON.mm",
                "Realm/RLMCredentials.mm",
                "Realm/RLMEmailPasswordAuth.mm",
                "Realm/RLMFindOneAndModifyOptions.mm",
                "Realm/RLMFindOptions.mm",
                "Realm/RLMMongoClient.mm",
                "Realm/RLMMongoCollection.mm",
                "Realm/RLMNetworkTransport.mm",
                "Realm/RLMProviderClient.mm",
                "Realm/RLMPushClient.mm",
                "Realm/RLMRealm+Sync.mm",
                "Realm/RLMSyncConfiguration.mm",
                "Realm/RLMSyncManager.mm",
                "Realm/RLMSyncSession.mm",
                "Realm/RLMSyncSubscription.mm",
                "Realm/RLMSyncUtil.mm",
                "Realm/RLMUpdateResult.mm",
                "Realm/RLMUser.mm",
                "Realm/RLMUserAPIKey.mm"
            ],
            publicHeadersPath: "include",
            cxxSettings: cxxSettings,
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS, .macCatalyst, .tvOS, .watchOS]))
            ]
        ),
        .target(
            name: "RealmSwift",
            dependencies: ["Realm"],
            path: "RealmSwift",
            exclude: [
                "Nonsync.swift",
                "RealmSwift-Info.plist",
                "Tests",
            ]
        ),
        .target(
            name: "RealmTestSupport",
            dependencies: ["Realm"],
            path: "Realm/TestUtils",
            cxxSettings: testCxxSettings
        ),
        .target(
            name: "RealmSwiftTestSupport",
            dependencies: ["RealmSwift", "RealmTestSupport"],
            path: "RealmSwift/Tests",
            sources: ["TestUtils.swift"]
        ),
        .testTarget(
            name: "RealmTests",
            dependencies: ["Realm", "RealmTestSupport"],
            path: "Realm/Tests",
            exclude: [
                "PrimitiveArrayPropertyTests.tpl.m",
                "PrimitiveDictionaryPropertyTests.tpl.m",
                "PrimitiveRLMValuePropertyTests.tpl.m",
                "PrimitiveSetPropertyTests.tpl.m",
                "RealmTests-Info.plist",
                "Swift",
                "SwiftUITestHost",
                "SwiftUITestHostUITests",
                "TestHost",
                "array_tests.py",
                "dictionary_tests.py",
                "fileformat-pre-null.realm",
                "mixed_tests.py",
                "set_tests.py",
                "SwiftUISyncTestHost",
                "SwiftUISyncTestHostUITests"
            ],
            cxxSettings: testCxxSettings
        ),
        .testTarget(
            name: "RealmObjcSwiftTests",
            dependencies: ["Realm", "RealmTestSupport"],
            path: "Realm/Tests/Swift",
            exclude: ["RealmObjcSwiftTests-Info.plist"]
        ),
        .testTarget(
            name: "RealmSwiftTests",
            dependencies: ["RealmSwift", "RealmTestSupport", "RealmSwiftTestSupport"],
            path: "RealmSwift/Tests",
            exclude: [
                "RealmSwiftTests-Info.plist",
                "QueryTests.swift.gyb",
                "TestUtils.swift"
            ]
        ),
      .target(name: "SetupBaas",
              path: "scripts/baas"),
      .plugin(name: "BaasPlugin",
              capability: .command(intent: .custom(verb: "build-ads", description: "Builds ADS Server"),
                                   permissions: [.writeToPackageDirectory(reason: "Server resources"),
                                                 .allowNetworkConnections(scope: .all(),
                                                                          reason: "Download Server resources")]),
//              dependencies: ["SetupBaas"],
              path: "scripts/plugins"),
        // Object server tests have support code written in both obj-c and
        // Swift which is used by both the obj-c and swift test code. SPM
        // doesn't support mixed targets, so this ends up requiring four
        // different targets.
        objectServerTestSupportTarget(
            name: "RealmSyncTestSupport",
            dependencies: ["Realm", "RealmSwift", "RealmTestSupport"],
            sources: ["RLMSyncTestCase.mm",
                      "RLMUser+ObjectServerTests.mm",
                      "RLMServerTestObjects.m"]
        ),
        objectServerTestSupportTarget(
            name: "RealmSwiftSyncTestSupport",
            dependencies: ["RealmSwift", "RealmTestSupport", "RealmSyncTestSupport", "RealmSwiftTestSupport"],
            sources: [
                 "SwiftSyncTestCase.swift",
                 "TimeoutProxyServer.swift",
                 "WatchTestUtility.swift",
                 "RealmServer.swift",
                 "SwiftServerObjects.swift"
            ]
        ),
        objectServerTestTarget(
            name: "SwiftObjectServerTests",
            sources: [
                "EventTests.swift",
                "SwiftAsymmetricSyncServerTests.swift",
                "SwiftCollectionSyncTests.swift",
                "SwiftFlexibleSyncServerTests.swift",
                "SwiftMongoClientTests.swift",
                "SwiftObjectServerPartitionTests.swift",
                "SwiftObjectServerTests.swift",
                "SwiftUIServerTests.swift"
            ]
        ),
        objectServerTestTarget(
            name: "ObjcObjectServerTests",
            sources: [
                "RLMAsymmetricSyncServerTests.mm",
                "RLMBSONTests.mm",
                "RLMCollectionSyncTests.mm",
                "RLMFlexibleSyncServerTests.mm",
                "RLMObjectServerPartitionTests.mm",
                "RLMObjectServerTests.mm",
                "RLMWatchTestUtility.m"
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
