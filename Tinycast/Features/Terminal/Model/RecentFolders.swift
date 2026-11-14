import Foundation

enum RecentFolders {
    static let maxCount = 12

    static func normalize(_ path: String, homeDirectory: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return standardize(homeDirectory) }
        let home = standardize(homeDirectory)
        let expanded: String
        if trimmed == "~" {
            expanded = home
        } else if trimmed.hasPrefix("~/") {
            expanded = home + String(trimmed.dropFirst())
        } else {
            expanded = trimmed
        }
        return standardize(expanded)
    }

    static func displayPath(_ path: String, homeDirectory: String) -> String {
        let normalized = normalize(path, homeDirectory: homeDirectory)
        let home = standardize(homeDirectory)
        if normalized == home { return "~" }
        if normalized.hasPrefix(home + "/") {
            return "~" + String(normalized.dropFirst(home.count))
        }
        return normalized
    }

    static func shortName(_ path: String, homeDirectory: String) -> String {
        let normalized = normalize(path, homeDirectory: homeDirectory)
        let home = standardize(homeDirectory)
        if normalized == home { return "~" }
        if normalized == "/" { return "/" }
        let last = (normalized as NSString).lastPathComponent
        return last.isEmpty ? normalized : last
    }

    static func record(
        _ path: String,
        in existing: [String],
        homeDirectory: String,
        maxCount: Int = maxCount
    ) -> [String] {
        let target = normalize(path, homeDirectory: homeDirectory)
        var result = [target]
        for folder in existing {
            let candidate = normalize(folder, homeDirectory: homeDirectory)
            if !result.contains(candidate) {
                result.append(candidate)
            }
            if result.count >= maxCount { break }
        }
        return result
    }

    // Cycling walks the list without reordering it, so repeated ⇧⇥ visits every folder.
    static func cycle(
        from current: String,
        in folders: [String],
        reverse: Bool = false,
        homeDirectory: String
    ) -> String {
        let normalizedFolders = deduplicated(folders, homeDirectory: homeDirectory)
        guard !normalizedFolders.isEmpty else {
            return normalize(current, homeDirectory: homeDirectory)
        }
        let target = normalize(current, homeDirectory: homeDirectory)
        guard let index = normalizedFolders.firstIndex(of: target) else {
            return normalizedFolders[0]
        }
        let count = normalizedFolders.count
        let step = reverse ? -1 : 1
        let next = (index + step + count) % count
        return normalizedFolders[next]
    }

    static func seeded(
        stored: [String],
        homeDirectory: String,
        currentDirectory: String? = nil,
        directoryExists: (String) -> Bool
    ) -> [String] {
        let home = standardize(homeDirectory)
        var candidates = stored
        if candidates.isEmpty {
            if let currentDirectory, currentDirectory != "/" {
                candidates.append(currentDirectory)
            }
            candidates.append(contentsOf: [
                home,
                home + "/Projects",
                home + "/Developer",
                home + "/Code",
                home + "/Desktop",
                home + "/Downloads",
                home + "/Documents"
            ])
        }
        let valid = deduplicated(candidates, homeDirectory: home)
            .filter(directoryExists)
        return valid.isEmpty ? [home] : Array(valid.prefix(maxCount))
    }

    private static func deduplicated(_ folders: [String], homeDirectory: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for folder in folders {
            let normalized = normalize(folder, homeDirectory: homeDirectory)
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    private static func standardize(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        guard standardized.count > 1, standardized.hasSuffix("/") else { return standardized }
        return String(standardized.dropLast())
    }
}
