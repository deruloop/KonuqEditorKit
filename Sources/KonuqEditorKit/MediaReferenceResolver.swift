import Foundation

enum MediaReferenceResolver {
	static let mediaScheme = "media:"
	static let defaultAppGroupIdentifier = "group.com.deruloop.Konuq"

	static func appGroupIdentifier() -> String {
		let raw = (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		if let raw, raw.isEmpty == false { return raw }
		return defaultAppGroupIdentifier
	}

	static func mediaDirectory() -> URL {
		let fm = FileManager.default
		let groupId = appGroupIdentifier()
		if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: groupId) {
			let dir = groupURL.appendingPathComponent("NoteMedia", isDirectory: true)
			if !fm.fileExists(atPath: dir.path) {
				try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
			}
			return dir
		}
		let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let dir = base.appendingPathComponent("NoteMedia", isDirectory: true)
		if !fm.fileExists(atPath: dir.path) {
			try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
		}
		return dir
	}

	static func makeMediaReference(filename: String) -> String {
		mediaScheme + filename
	}

	static func localFileURL(from reference: String) -> URL? {
		if reference.hasPrefix(mediaScheme) {
			let filename = String(reference.dropFirst(mediaScheme.count))
			guard filename.isEmpty == false else { return nil }
			return mediaDirectory().appendingPathComponent(filename)
		}
		if let url = URL(string: reference), url.isFileURL {
			return url
		}
		if reference.hasPrefix("/") {
			return URL(fileURLWithPath: reference)
		}
		return nil
	}
}

