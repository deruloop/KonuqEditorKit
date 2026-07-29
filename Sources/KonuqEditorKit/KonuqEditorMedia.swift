import UIKit
import Photos

/// Resolves the editor's media references (`media:<file>` package/app-group files, or
/// `phasset:<localIdentifier>` Photos assets) into image bytes a host app can hand off.
public enum KonuqEditorMedia {

	/// Load a media reference as web-safe JPEG data, downscaled to `maxDimension`.
	/// Returns nil if the reference can't be resolved.
	@MainActor
	public static func loadJPEGData(for reference: String, maxDimension: CGFloat = 2048, quality: CGFloat = 0.9) async -> Data? {
		if reference.hasPrefix("phasset:") {
			let id = String(reference.dropFirst("phasset:".count))
			guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
			let data: Data? = await withCheckedContinuation { continuation in
				let options = PHImageRequestOptions()
				options.isNetworkAccessAllowed = true
				options.deliveryMode = .highQualityFormat
				options.isSynchronous = false
				PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
					continuation.resume(returning: data)
				}
			}
			guard let data, let image = UIImage(data: data) else { return nil }
			return downscaled(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
		}

		guard let url = MediaReferenceResolver.localFileURL(from: reference),
			  let image = UIImage(contentsOfFile: url.path) else { return nil }
		return downscaled(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
	}

	private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
		let longest = max(image.size.width, image.size.height)
		guard longest > maxDimension, longest > 0 else { return image }
		let scale = maxDimension / longest
		let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
		let renderer = UIGraphicsImageRenderer(size: size)
		return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
	}
}
