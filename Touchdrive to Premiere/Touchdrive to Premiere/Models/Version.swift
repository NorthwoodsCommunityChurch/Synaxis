//
//  Version.swift
//  Synaxis
//
//  Single source of truth for app version.
//

import Foundation

/// Represents a semantic version with optional pre-release tag.
struct Version: Comparable, CustomStringConvertible, Equatable {

    /// Current app version. Update this when releasing new versions.
    static let current = Version(string: "1.0.4")!

    let major: Int
    let minor: Int
    let patch: Int
    let preRelease: String?

    var description: String {
        var str = "\(major).\(minor).\(patch)"
        if let pre = preRelease {
            str += "-\(pre)"
        }
        return str
    }

    /// Parse version string like "v2.3.0", "2.3.0", or "2.3.0-beta".
    init?(string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: "-", maxSplits: 1)
        let versionPart = parts[0]
        let preReleasePart = parts.count > 1 ? String(parts[1]) : nil

        let numbers = versionPart.split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 3 else { return nil }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        preRelease = preReleasePart
    }

    init(major: Int, minor: Int, patch: Int, preRelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.preRelease = preRelease
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Pre-release < release (1.0.0-alpha < 1.0.0)
        if lhs.preRelease != nil && rhs.preRelease == nil { return true }
        if lhs.preRelease == nil && rhs.preRelease != nil { return false }

        // Both have pre-release: compare alphabetically
        if let lp = lhs.preRelease, let rp = rhs.preRelease {
            return lp < rp
        }
        return false
    }
}
