import Foundation
import UniformTypeIdentifiers

/// Turns dropped or chosen items into the files Dice opens: folders contribute the images inside them.
public enum ImageFiles {
    public static let folderLimit = 500
    static let accepted: [UTType] = [.image, .svg, .pdf]
    /// Files pass through unchanged (unsupported ones still show their error); folders are searched recursively,
    /// skipping hidden files and package contents, up to `limit` images. `truncated` reports a folder cut short.
    public static func expand(_ urls: [URL], limit: Int = folderLimit) -> (urls: [URL], truncated: Bool) {
        var files: [URL] = [], found = 0, truncated = false
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else { files.append(url); continue }
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var inside: [URL] = []
            for case let file as URL in enumerator {
                guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let type = values.contentType, accepted.contains(where: { type.conforms(to: $0) }) else { continue }
                if found == limit { truncated = true; break }
                inside.append(file); found += 1
            }
            files += inside.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        return (files, truncated)
    }
}
