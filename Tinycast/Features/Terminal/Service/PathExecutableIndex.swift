import Foundation

enum PathExecutableIndex {
    private static let standardDirectories = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    @concurrent
    static func scan(homeDirectory: String, environmentPath: String?) async -> Set<String> {
        var directories: [String] = []
        if let environmentPath {
            directories.append(contentsOf: environmentPath.split(separator: ":").map(String.init))
        }
        directories.append(contentsOf: standardDirectories)
        directories.append(contentsOf: [
            homeDirectory + "/.local/bin",
            homeDirectory + "/.cargo/bin",
            homeDirectory + "/.bun/bin",
            homeDirectory + "/go/bin"
        ])

        let fm = FileManager.default
        var seenDirs = Set<String>()
        var names = Set<String>()
        for rawDir in directories where !rawDir.isEmpty {
            let dir = (rawDir as NSString).expandingTildeInPath
            guard seenDirs.insert(dir).inserted else { continue }
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                names.insert(entry)
            }
        }
        return names
    }
}
