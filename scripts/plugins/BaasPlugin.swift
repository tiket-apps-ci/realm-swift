import Foundation
import PackagePlugin

enum Error : Swift.Error {
    case error(_ message: String)
}
@discardableResult // Add to suppress warnings when you don't want/need a result
func shell(_ command: String, environment: [String : String] = [:]) throws -> (output: String, terminationStatus: Int32) {
    let task = Process()
    let pipe = Pipe()
    pipe.fileHandleForReading.readabilityHandler = {
        guard let str = String(data: $0.availableData, encoding: .utf8), !str.isEmpty else {
            return
        }
        print(str)
    }
    if !environment.isEmpty {
        task.environment = environment
    }
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh") //<--updated
    task.standardInput = nil

    try task.run()
    task.waitUntilExit() //<--updated
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    print("SHELL: \(output)")
    if task.terminationStatus != 0 {
        throw Error.error(output)
    }
    return (output, task.terminationStatus)
}

@discardableResult // Add to suppress warnings when you don't want/need a result
func shell2(executableURL: URL, arguments: [String], environment: [String : String] = [:]) throws -> (output: String, terminationStatus: Int32) {
    let task = Process()
    let pipe = Pipe()
    pipe.fileHandleForReading.readabilityHandler = {
        guard let str = String(data: $0.availableData, encoding: .utf8), !str.isEmpty else {
            return
        }
        print(str)
    }
    if !environment.isEmpty {
        task.environment = environment
    }
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = arguments
    task.executableURL = executableURL
    task.standardInput = nil

    try task.run()
    task.waitUntilExit() //<--updated
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    print("SHELL: \(output)")
    if task.terminationStatus != 0 {
        throw Error.error(output)
    }
    return (output, task.terminationStatus)
}

@available(macOS 13.0, *)
@main struct ADSPlugin : CommandPlugin {
    struct Build {
        let pluginWorkDirectory: String
        let dependenciesFilePath: String
        
        let fm = FileManager.default
        lazy var BASE_DIR = pluginWorkDirectory
        lazy var BUILD_DIR = "\(BASE_DIR)/.baas"
        lazy var BIN_DIR = "\(BUILD_DIR)/bin"
        lazy var LIB_DIR = "\(BUILD_DIR)/lib"
        lazy var PID_FILE = "\(BUILD_DIR)/pid.txt"
        
        lazy var MONGO_EXE = "'\(BIN_DIR)'/mongo"
        lazy var MONGOD_EXE = "'\(BIN_DIR)'/mongod"
        
        lazy var DEPENDENCIES: [String : String] = {
            let data: Data = try! Data(contentsOf: URL(filePath: dependenciesFilePath))
            return String(data: data, encoding: .utf8)!
                .split(separator: "\n")
                .map {
                    $0.split(separator: "=").map(String.init)
                }.reduce(into: [String: String](), {
                    $0[$1[0]] = $1[1]
                })
        }()
        
        lazy var MONGODB_VERSION = "5.0.6"
        lazy var GO_VERSION = "1.21.1"
        lazy var NODE_VERSION = "16.13.1"
        lazy var STITCH_VERSION = "911b8db03b852f664af13880c42eb8178d4fb5f4"// DEPENDENCIES["STITCH_VERSION"]!
        
        lazy var MONGODB_URL = "https://fastdl.mongodb.org/osx/mongodb-macos-x86_64-\(MONGODB_VERSION).tgz"
        let TRANSPILER_TARGET = "node16-macos"
        let SERVER_STITCH_LIB_URL = "https://s3.amazonaws.com/stitch-artifacts/stitch-support/stitch-support-macos-debug-4.3.2-721-ge791a2e-patch-5e2a6ad2a4cf473ae2e67b09.tgz"
        let STITCH_SUPPORT_URL="https://static.realm.io/downloads/swift/stitch-support.tar.xz"
        lazy var MONGO_DIR = "\(BUILD_DIR)/mongodb-macos-x86_64-\(MONGODB_VERSION)"
        /// The directory where mongo stores its files. This is a unique value so that
        /// we have a fresh mongo each run.
        private lazy var tempDir = URL(fileURLWithPath: NSTemporaryDirectory(),
                                       isDirectory: true).appendingPathComponent("realm-test-\(UUID().uuidString)")
        lazy var go_root = "\(BUILD_DIR)/go"
        
        mutating func setUpDirectoryStructure() throws {
            guard !fm.fileExists(atPath: BUILD_DIR) else {
                return
            }
            try fm.createDirectory(atPath: BUILD_DIR,
                                   withIntermediateDirectories: false)
            try fm.createDirectory(atPath: BIN_DIR,
                                   withIntermediateDirectories: false)
            try fm.createDirectory(atPath: LIB_DIR,
                                   withIntermediateDirectories: false)
        }
        
        mutating func setUpMongod() async throws {
            guard !fm.fileExists(atPath: BIN_DIR + "/mongo") else { return }
            let (data, _) = try await URLSession(configuration: .default)
                .data(from: URL(string: MONGODB_URL)!)
            try data.write(to: URL(filePath: "\(MONGO_DIR).tgz"))
            try fm.createDirectory(atPath: MONGO_DIR,
                                   withIntermediateDirectories: false)
            try shell("tar xzf \(MONGO_DIR).tgz --directory \(BUILD_DIR)")
            try fm.copyItem(at: URL(filePath: MONGO_DIR)
                .appending(path: "bin")
                .appending(path: "mongo"),
                            to: URL(filePath: BIN_DIR).appending(path: "mongo"))
            try fm.copyItem(at: URL(filePath: MONGO_DIR)
                .appending(path: "bin")
                .appending(path: "mongod"),
                            to: URL(filePath: BIN_DIR).appending(path: "mongod"))
        }
        
        /// Launch the mongo server in the background.
        /// This process should run until the test suite is complete.
        mutating func launchMongoProcess() throws {
            try! fm.createDirectory(at: tempDir,
                                    withIntermediateDirectories: false,
                                    attributes: nil)
            let mongoProcess = Process()
            mongoProcess.launchPath = URL(filePath: BIN_DIR).appendingPathComponent("mongod").path
            mongoProcess.arguments = [
                "--quiet",
                "--dbpath", tempDir.path,
                "--bind_ip", "localhost",
                "--port", "26000",
                "--replSet", "test"
            ]
            mongoProcess.standardOutput = nil
            try mongoProcess.run()
            
            let initProcess = Process()
            initProcess.launchPath = URL(filePath: BIN_DIR).appendingPathComponent("mongo").path
            initProcess.arguments = [
                "--port", "26000",
                "--eval", "rs.initiate()"
            ]
            initProcess.standardOutput = nil
            try initProcess.run()
            initProcess.waitUntilExit()
            mongoProcess.terminate()
        }
        
        mutating func setUpGoLang() throws {
            guard !fm.fileExists(atPath: "\(go_root)/bin/go") else { return }
            print("downloading go")
            try shell("cd \(BUILD_DIR) && curl --silent 'https://dl.google.com/go/go\(GO_VERSION).darwin-amd64.tar.gz' | tar xz")
            try shell("mkdir -p \(go_root)/src/github.com/10gen")
        }
        
        mutating func checkoutBaas() throws {
            let stitch_dir = "\(BUILD_DIR)/baas"
            if !fm.fileExists(atPath: stitch_dir) {
                print("cloning stitch")
                try shell("git clone git@github.com:10gen/baas \(stitch_dir)")
            } else {
                print("stitch dir exists")
            }
            print("checking out stitch")
            let stitch_worktree = "\(go_root)/src/github.com/10gen/baas"
            if fm.fileExists(atPath: "\(stitch_dir)/.git") {
                // Fetch the BaaS version if we don't have it
                try shell("git -C '\(stitch_dir)' show-ref --verify --quiet \(STITCH_VERSION) || git -C '\(stitch_dir)' fetch")
                // Set the worktree to the correct version
                if fm.fileExists(atPath: stitch_worktree) {
                    try shell("git -C '\(stitch_worktree)' checkout \(STITCH_VERSION)")
                } else {
                    try shell("git -C '\(stitch_dir)' worktree add '\(stitch_worktree)' \(STITCH_VERSION)")
                }
            } else {
                // We have a stitch directory with no .git directory, meaning we're
                // running on CI and just need to copy the files into place
                if !fm.fileExists(atPath: stitch_worktree) {
                    try shell("cp -Rc '\(stitch_dir)' '\(stitch_worktree)'")
                }
            }
        }
        
        mutating func setUpSupportLibs() throws {
            if !fm.fileExists(atPath: "\(BUILD_DIR)/stitch-support.tar.xz") {
                print("downloading stitch support")
                try shell("cd \(BUILD_DIR) && curl --silent -O \(STITCH_SUPPORT_URL)")
            }
            
            let stitch_dir = "\(go_root)/src/github.com/10gen/baas"
            if !fm.fileExists(atPath: "\(LIB_DIR)/libstitch_support.dylib") {
                try fm.createDirectory(atPath: "\(stitch_dir)/etc/dylib/include/stitch_support/v1/stitch_support", withIntermediateDirectories: true)
                try shell("tar --extract --strip-components=1 -C '\(stitch_dir)/etc/dylib' --file '\(BUILD_DIR)/stitch-support.tar.xz' stitch-support/lib stitch-support/include")
                try fm.copyItem(atPath: "\(stitch_dir)/etc/dylib/lib/libstitch_support.dylib", toPath: "\(LIB_DIR)/libstitch_support.dylib")
                try fm.copyItem(atPath: "\(stitch_dir)/etc/dylib/include/stitch_support.h", toPath: "\(stitch_dir)/etc/dylib/include/stitch_support/v1/stitch_support/stitch_support.h")
            }
            
            let update_doc_filepath = "\(BIN_DIR)/update_doc"
            if !fm.fileExists(atPath: update_doc_filepath) {
                try shell("tar --extract --strip-components=2 -C '\(BIN_DIR)' --file '\(BUILD_DIR)/stitch-support.tar.xz' stitch-support/bin/update_doc")
                try shell("chmod +x '\(update_doc_filepath)'")
            }
            
            let assisted_agg_filepath = "\(BIN_DIR)/assisted_agg"
            if !fm.fileExists(atPath: assisted_agg_filepath) {
                try shell("tar --extract --strip-components=2 -C '\(BIN_DIR)' --file '\(BUILD_DIR)/stitch-support.tar.xz' stitch-support/bin/assisted_agg")
                try shell("chmod +x '\(assisted_agg_filepath)'")
            }
        }
        
        mutating func setUpTranspiler(exports: inout [String : String]) throws {
            if !fm.fileExists(atPath: "\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64") {
                print("downloading node 🚀")
                try shell("cd '\(BUILD_DIR)' && curl -O 'https://nodejs.org/dist/v\(NODE_VERSION)/node-v\(NODE_VERSION)-darwin-x64.tar.gz' && tar xzf node-v\(NODE_VERSION)-darwin-x64.tar.gz")
            }
            fm.createFile(atPath: "\(BUILD_DIR)/.yarnrc.yml",
                          contents: "global-folder \"\(BUILD_DIR)/.yarn/global\"".data(using: .utf8))
            let stitch_dir = "\(go_root)/src/github.com/10gen/baas"
            exports["npm_config_cache"] = "\(BUILD_DIR)/.npm"
            exports["YARN_CACHE_FOLDER"] = "\(BUILD_DIR)/.yarn/cache"
            exports["YARN_GLOBAL_FOLDER"] = "\(BUILD_DIR)/.yarn/global"
            exports["PKG_CACHE_PATH"] = "\(BUILD_DIR)/.pkg_cache"
            exports["GOMODCACHE"] = "\(BUILD_DIR)/.go_mod_cache"
            exports["GOCACHE"] = "\(BUILD_DIR)/.go_cache"
            exports["GO111MODULE"] = "on"
            exports["YARN_ENABLE_GLOBAL_CACHE"] = "0"
//            exports["NODE_PATH"] = "\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin"
//            exports["NPM_PATH"] = "\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin"
            exports["GOROOT"] = go_root
            exports["STITCH_PATH"] = stitch_dir
            exports["PATH"] = "$GOROOT/bin/:$STITCH_PATH/etc/transpiler/bin/:\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin:/usr/local/bin/:/usr/bin/:\(BUILD_DIR)/yarn/bin/:$PATH"
            exports["DYLD_LIBRARY_PATH"] = LIB_DIR
//            exports["GOPRIVATE"] = "github.com/10gen"
            exports["GOENV"] = "\(go_root)/.env"
            exports["HOME"] = BUILD_DIR
            exports["GIT_CONFIG"] = "\(BUILD_DIR)/.gitconfig"
            try """
            [url "ssh://git@github.com"]
                insteadOf = https://github.com
            """.write(toFile: "\(BUILD_DIR)/.gitconfig", atomically: true, encoding: .utf8)
            try """
            GOPRIVATE=github.com/10gen/*
            GOMODCACHE="\(BUILD_DIR)/.go_mod_cache"
            GOCACHE="\(BUILD_DIR)/.go_cache"
            """.write(toFile: "\(go_root)/.env", atomically: true, encoding: .utf8)
//            exports["GOPATH"] = go_root
//            if ((try? shell("which yarn").terminationStatus != 0) != nil) {
//                try shell("rm -rf '$HOME/.yarn'")
            try? fm.createDirectory(atPath: "\(BUILD_DIR)/.yarn/global", withIntermediateDirectories: true)
            let nodeURL = URL(filePath: "\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin/node")
            let npmURL = URL(filePath: "\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin/npm")
            print("adding yarn")
//            try shell2(executableURL: nodeURL, arguments: [
//                "add", "yarn@https://github.com/yarnpkg/yarn"
//            ], environment: exports)
            if !fm.fileExists(atPath: "\(BUILD_DIR)/yarn/bin/yarn") {
                print("installing yarn 🧶")
                try shell("cd \(BUILD_DIR) && curl -O -L 'https://yarnpkg.com/latest.tar.gz'")
                try? fm.createDirectory(atPath: "\(BUILD_DIR)/yarn", withIntermediateDirectories: true)
                try shell("cd \(BUILD_DIR) && tar xzf latest.tar.gz -C yarn --strip-components=1")
            }
//            try shell2(executableURL: nodeURL, arguments: [
//                nodeURL.deletingLastPathComponent().appending(component: "npm").path(), "install",
//                "--global",
//                 /*"-S",*/ "yarn"
//            ], environment: exports)
//                try shell("""
//            export PATH=\"\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin/:$PATH\" && curl -o- -L https://yarnpkg.com/install.sh | bash
//            """)
//                exports.append("export PATH=\"$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH\"")
//            exports.append("export PATH=")
//            }
//            exports.append("export PATH=\"\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin/node_modules/.bin:$PATH\"")
            print("building transpiler")
//            try shell("\(exports.joined(separator: " && ") + " && ") yarn config set global-folder '\(BUILD_DIR)/.yarn_bin'")
            guard !fm.fileExists(atPath: "\(BIN_DIR)/transpiler") else {
                return
            }
            // Install a newer version of pkg that actually supports recent versions of node
//            try shell("""
//            \(exports.joined(separator: " && ") + " && ") \
//            cd '\(stitch_dir)/etc/transpiler' && yarn --use-yarnrc \(BUILD_DIR)/.yarnrc.yml add pkg
//            """)
//            try shell("""
//            \(exports.joined(separator: " && ") + " && ") \
//            yarn version
//            """)
//            try shell("""
//        \(exports.joined(separator: " && ") + " && ") \
//            cd '\(stitch_dir)/etc/transpiler' && yarn install --use-yarnrc \(BUILD_DIR)/.yarnrc && yarn --use-yarnrc \(BUILD_DIR)/.yarnrc run build -t "\(TRANSPILER_TARGET)" &&
//            cp -c bin/transpiler \(BUILD_DIR)/bin
//        """)

//            try shell("""
//            \(exports.joined(separator: " && ") + " && ") \
//                yarn config set global-folder \(BUILD_DIR)/.yarn/global 
//            """)
//            try shell("""
//        \(exports.joined(separator: " && ") + " && ") \
//            cd '\(stitch_dir)/etc/transpiler' && yarn --use-yarnrc \(BUILD_DIR)/.yarnrc build &&
//            cp -c bin/transpiler \(BUILD_DIR)/bin
//        """, environment: [
//            "YARN_GLOBAL_FOLDER": "\(BUILD_DIR)/.yarn/global",
//            "YARN_ENABLE_GLOBAL_CACHE": "0"
//        ])
            
//            try shell("""
//                    \(exports.joined(separator: " && ") + " && ") \
//            yarn --use-yarnrc "\(BUILD_DIR)/.yarnrc.yml" config set prefix \(BUILD_DIR)
//            """, environment: ["PATH":"\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin/node_modules/.bin/:$PATH"])
            let yarnURL = URL(filePath: "\(BUILD_DIR)/yarn/bin/yarn")
            let yarnPkgURL = URL(filePath: "\(BUILD_DIR)/yarn/bin/yarnpkg")
//            let yarnURL = URL(filePath: "\(BUILD_DIR)/node-v\(NODE_VERSION)-darwin-x64/bin/yarn")
            try shell2(executableURL: yarnURL, arguments: [
                "--cwd", "\(stitch_dir)/etc/transpiler",
                "--use-yarnrc", "\(BUILD_DIR)/.yarnrc.yml",
                "--global-folder", "\(BUILD_DIR)/.yarn/global",
                "install"
            ], environment: exports)
//            try shell2(executableURL: yarnURL, arguments: [
//                "--cwd", "\(stitch_dir)/etc/transpiler",
//                "--use-yarnrc", "\(BUILD_DIR)/.yarnrc.yml",
//                "config", "set", "global-folder", "\(BUILD_DIR)/.yarn/global"
//            ], environment: exports)
//            try shell2(executableURL: npmURL, arguments: [
//                
//                "run", "build", "--prefix", "\(stitch_dir)/etc/transpiler/",
//            ], environment: exports)
            _ = try? shell2(executableURL: yarnPkgURL, arguments: [
                "--cwd", "\(stitch_dir)/etc/transpiler",
                "--use-yarnrc", "\(BUILD_DIR)/.yarnrc.yml",
                "--global-folder", "\(BUILD_DIR)/.yarn/global",
                "--link-folder", "\(BUILD_DIR)/.yarn/global",
                "build", "-t", "node16-macos-x64"
            ], environment: exports)
//            try shell2(executableURL: yarnURL, arguments: ["""
//            cd '\(stitch_dir)/etc/transpiler' && yarn build  --global-folder \(BUILD_DIR)/.yarn/global --use-yarnrc \(BUILD_DIR)/.yarnrc.yml  && \
//            cp -c bin/transpiler \(BUILD_DIR)/bin
//        """], environment: exports)
//            Showing All Messages
//            $ pkg ./index.js -o bin/transpiler


            print("TRANSPILER SIZE")
            try shell("ls -l \(stitch_dir)/etc/transpiler/bin")
            
            try fm.copyItem(atPath: "\(stitch_dir)/etc/transpiler/bin/transpiler", toPath: "\(BUILD_DIR)/bin/transpiler")
        }
        
        mutating func buildCreateUserBinary(exports: inout [String: String]) throws {
            let stitch_dir = "\(go_root)/src/github.com/10gen/baas"

            print("build create_user binary")
            
            if !fm.fileExists(atPath: "\(BIN_DIR)/create_user") {
                try? fm.createDirectory(atPath: "\(BUILD_DIR)/.go_cache", withIntermediateDirectories: true)
                try? fm.createDirectory(atPath: "\(BUILD_DIR)/.go_mod_cache", withIntermediateDirectories: true)
//                try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"),
//                           arguments: ["get"]
////                cp -c create_user '\(BIN_DIR)'
//            , environment: exports)
//                try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"),
//                           arguments: [
//                            "mod", "tidy", "github.com/10gen/baas"
//                           ]
////                cp -c create_user '\(BIN_DIR)'
//                           , environment: exports)
                try shell("cd \(stitch_dir) && \(go_root)/bin/go build -o create_user cmd/auth/user.go", environment: exports)
                try fm.copyItem(atPath: "\(stitch_dir)/create_user", toPath: "\(BIN_DIR)/create_user")
//                try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"),
//                           arguments: [
//                            "build", "-o", "create_user",
//                            "github.com/10gen/baas/cmd/auth/user.go",
//                           ]
                
//                           , environment: exports)
//                try fm.removeItem(atPath: "\(BUILD_DIR)/.go_cache")
//                try fm.removeItem(atPath: "\(BUILD_DIR)/.go_mod_cache")
                print("create_user binary built")
            }
            
        }
        
        mutating func buildServerBinary(exports: inout [String: String]) throws {
            guard !fm.fileExists(atPath: "\(BIN_DIR)/stitch_server") else {
                return
            }
            let stitch_dir = "\(go_root)/src/github.com/10gen/baas"
            try? fm.createDirectory(atPath: "\(BUILD_DIR)/.go_cache", withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: "\(BUILD_DIR)/.go_mod_cache", withIntermediateDirectories: true)
            print("building server binary")
  
//            try shell2(executableURL: URL(filePath: "/usr/bin/git"), arguments: [
//                "config", "--global", "--add", "url.\"git@github.com:\".insteadOf  \"https://github.com/\""
//            ])
            try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"),
                       arguments: ["env"],
                       environment: exports)
            try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"),
                       arguments: ["env", "-w", "GOPRIVATE=*"],
                       environment: exports)
            try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"), arguments: [
                "build", "-C", "\(stitch_dir)", "-o", "stitch_server", "cmd/server/main.go"
            ], environment: exports)
//            try shell2(executableURL: URL(filePath: "\(go_root)/bin/go"),
//                       arguments: ["get", "-C", stitch_dir, "-u", "git@github.com:10gen/mongonet"],
//                       environment: exports)
//            try shell("""
//            cd \(stitch_dir) && \
//            \(go_root)/bin/go build -o stitch_server cmd/server/main.go
//            """, environment: exports)
            try fm.copyItem(atPath: "\(stitch_dir)/stitch_server", toPath: "\(BIN_DIR)/stitch_server")
            print("server binary built")
        }
        
        init(pluginWorkDirectory: String, dependenciesFilePath: String) {
            self.pluginWorkDirectory = pluginWorkDirectory
            self.dependenciesFilePath = dependenciesFilePath
        }
    }
    
    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        print("Working directory: \(context.pluginWorkDirectory.string)")
        var app = Build.init(pluginWorkDirectory: context.pluginWorkDirectory.string,
                             dependenciesFilePath: context.package.directory.appending("dependencies.list").string)
        try app.setUpDirectoryStructure()
        try await app.setUpMongod()
        try app.launchMongoProcess()
        try app.setUpGoLang()
        try app.checkoutBaas()
        try app.setUpSupportLibs()
        var exports: [String: String] = [:]
        try app.setUpTranspiler(exports: &exports)
        try app.buildCreateUserBinary(exports: &exports)
        try app.buildServerBinary(exports: &exports)
        print("copying resources to package")
        let stitch_dir = "\(app.go_root)/src/github.com/10gen/baas"
        try? app.fm.createDirectory(at: URL(filePath: context.package.directory.appending(".baas").string), withIntermediateDirectories: true)
        try? app.fm.createDirectory(at: URL(filePath: context.package.directory
            .appending(".baas")
            .appending("\(app.go_root)/src/github.com/10gen/baas/etc/configs")
            .string), withIntermediateDirectories: true)
        try shell("cp -R \(app.BUILD_DIR)/bin \(context.package.directory.appending(".baas"))")
        try shell("cp -R \(app.BUILD_DIR)/lib \(context.package.directory.appending(".baas"))")
        
        try shell("cp -R \(stitch_dir)/etc/configs/ \(context.package.directory.appending(".baas"))")
                    
//        try app.fm.copyItem(atPath: "\(app.BUILD_DIR)/*", toPath: context.package.directory.appending(".baas").appending("*").string)// app.BUILD_DIR
    }
}
