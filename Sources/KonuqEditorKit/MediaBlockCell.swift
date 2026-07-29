import UIKit
import Photos
import AVFoundation

protocol MediaBlockCellDelegate: AnyObject {
	func mediaBlockCell(_ cell: MediaBlockCell, didChangeDisplayStyle displayStyle: MediaBlockDisplayStyle)
	func mediaBlockCellDidTapMedia(_ cell: MediaBlockCell)
}

final class MediaBlockCell: UITableViewCell, BlockSelectableCell {
	static let reuseId = "MediaBlockCell"

	weak var delegate: MediaBlockCellDelegate?
	private(set) var blockId: String = ""
	private var reference: String = ""
	private var kind: MediaBlockKind = .image
	private var displayStyle: MediaBlockDisplayStyle = .medium
	private var currentImageRequestId: PHImageRequestID?

	private let cardView = UIView()
	private let mediaView = UIImageView()
	private let compactOverlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
	private let compactStyleButton = UIButton(type: .system)
	private let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))

	var isSelectionMode: Bool = false {
		didSet {
			updateSelectionAppearance()
		}
	}

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)

		selectionStyle = .none
		backgroundColor = .clear
		contentView.backgroundColor = .clear

		contentView.addSubview(cardView)
		cardView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
			cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
			cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
			cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
		])
		cardView.layer.cornerRadius = 12
		cardView.layer.masksToBounds = true
		cardView.backgroundColor = .clear

		mediaView.translatesAutoresizingMaskIntoConstraints = false
		mediaView.contentMode = .scaleAspectFill
		mediaView.clipsToBounds = true
		mediaView.isUserInteractionEnabled = true
		mediaView.layer.cornerRadius = 16
		mediaView.layer.masksToBounds = true
		mediaView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.8)
		cardView.addSubview(mediaView)

		NSLayoutConstraint.activate([
			mediaView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
			mediaView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
			mediaView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
			mediaView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
		])

		compactOverlay.translatesAutoresizingMaskIntoConstraints = false
		compactOverlay.layer.cornerRadius = 10
		compactOverlay.layer.masksToBounds = true
		mediaView.addSubview(compactOverlay)

		compactStyleButton.translatesAutoresizingMaskIntoConstraints = false
		compactStyleButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
		compactStyleButton.showsMenuAsPrimaryAction = true
		compactOverlay.contentView.addSubview(compactStyleButton)

		NSLayoutConstraint.activate([
			compactOverlay.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: 8),
			compactOverlay.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: -8),
			compactOverlay.heightAnchor.constraint(equalToConstant: 32),
			compactOverlay.widthAnchor.constraint(equalTo: compactOverlay.heightAnchor),

			compactStyleButton.topAnchor.constraint(equalTo: compactOverlay.contentView.topAnchor),
			compactStyleButton.bottomAnchor.constraint(equalTo: compactOverlay.contentView.bottomAnchor),
			compactStyleButton.leadingAnchor.constraint(equalTo: compactOverlay.contentView.leadingAnchor),
			compactStyleButton.trailingAnchor.constraint(equalTo: compactOverlay.contentView.trailingAnchor),
		])

		playIcon.translatesAutoresizingMaskIntoConstraints = false
		playIcon.contentMode = .center
		playIcon.clipsToBounds = true
		playIcon.image = UIImage(
			systemName: "play.fill",
			withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
		)
		playIcon.tintColor = UIColor.white
		playIcon.backgroundColor = UIColor.black.withAlphaComponent(0.35)
		playIcon.layer.cornerRadius = 18
		playIcon.layer.masksToBounds = true
		mediaView.addSubview(playIcon)

		NSLayoutConstraint.activate([
			playIcon.centerXAnchor.constraint(equalTo: mediaView.centerXAnchor),
			playIcon.centerYAnchor.constraint(equalTo: mediaView.centerYAnchor),
			playIcon.widthAnchor.constraint(equalToConstant: 36),
			playIcon.heightAnchor.constraint(equalToConstant: 36),
		])

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTapMedia(_:)))
		mediaView.addGestureRecognizer(tap)

		updateSelectionAppearance()
		updateCompactStyleTitle()
		compactStyleButton.menu = makeStyleMenu()
	}

	required init?(coder: NSCoder) {
		fatalError()
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		if let currentImageRequestId {
			PHImageManager.default().cancelImageRequest(currentImageRequestId)
		}
		currentImageRequestId = nil
		mediaView.image = nil
	}

	func configure(blockId: String, kind: MediaBlockKind, reference: String, displayStyle: MediaBlockDisplayStyle) {
		self.blockId = blockId
		self.kind = kind
		self.reference = reference
		self.displayStyle = displayStyle

		playIcon.isHidden = (kind == .image)
		updateCompactStyleTitle()
		compactStyleButton.menu = makeStyleMenu()
		updateHeight()
		loadMedia()
		updateSelectionAppearance()
	}

	private func updateHeight() {
		let height: CGFloat = {
			switch displayStyle {
			case .small: 140
			case .medium: 220
			case .large: 320
			}
		}()

		for c in mediaView.constraints {
			if c.firstAttribute == .height {
				c.isActive = false
			}
		}
		mediaView.heightAnchor.constraint(equalToConstant: height).isActive = true
	}

	private func updateCompactStyleTitle() {
		let label: String = {
			switch displayStyle {
			case .small: "S"
			case .medium: "M"
			case .large: "L"
			}
		}()
		compactStyleButton.setTitle(label, for: .normal)
	}

	private func makeStyleMenu() -> UIMenu {
		let actionSmall = UIAction(
			title: "Small",
			state: displayStyle == .small ? .on : .off
		) { [weak self] _ in
			self?.applyDisplayStyle(.small)
		}

		let actionMedium = UIAction(
			title: "Medium",
			state: displayStyle == .medium ? .on : .off
		) { [weak self] _ in
			self?.applyDisplayStyle(.medium)
		}

		let actionLarge = UIAction(
			title: "Large",
			state: displayStyle == .large ? .on : .off
		) { [weak self] _ in
			self?.applyDisplayStyle(.large)
		}

		return UIMenu(children: [actionSmall, actionMedium, actionLarge])
	}

	private func applyDisplayStyle(_ newStyle: MediaBlockDisplayStyle) {
		displayStyle = newStyle
		updateCompactStyleTitle()
		compactStyleButton.menu = makeStyleMenu()
		updateHeight()
		delegate?.mediaBlockCell(self, didChangeDisplayStyle: newStyle)
	}

	private func loadMedia() {
		if reference.hasPrefix("phasset:") {
			let id = String(reference.dropFirst("phasset:".count))
			let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
			guard let asset = assets.firstObject else { return }

			let options = PHImageRequestOptions()
			options.isNetworkAccessAllowed = true
			options.resizeMode = .fast
			options.deliveryMode = .opportunistic

			let targetSize = CGSize(width: 1200, height: 1200)
			currentImageRequestId = PHImageManager.default().requestImage(
				for: asset,
				targetSize: targetSize,
				contentMode: .aspectFill,
				options: options
			) { [weak self] image, _ in
				guard let self else { return }
				DispatchQueue.main.async {
					self.mediaView.image = image
				}
			}
			return
		}

		if let url = MediaReferenceResolver.localFileURL(from: reference) {
			if kind == .image {
				if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
					DispatchQueue.main.async {
						self.mediaView.image = image
					}
				}
			} else {
				let videoURL = url
				DispatchQueue.global(qos: .userInitiated).async { [weak self] in
					guard let self else { return }
					let asset = AVAsset(url: videoURL)
					let generator = AVAssetImageGenerator(asset: asset)
					generator.appliesPreferredTrackTransform = true
					generator.maximumSize = CGSize(width: 1200, height: 1200)

					let image: UIImage? = {
						let time = CMTime(seconds: 0.2, preferredTimescale: 600)
						guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
						return UIImage(cgImage: cgImage)
					}()

					DispatchQueue.main.async {
						self.mediaView.image = image ?? UIImage(systemName: "video")
					}
				}
			}
		}
	}

	private func updateSelectionAppearance() {
		if isSelectionMode && isSelected {
			cardView.layer.borderWidth = 2
			cardView.layer.borderColor = UIColor.appAccent.cgColor
			cardView.backgroundColor = UIColor.appAccent.withAlphaComponent(0.06)
		} else {
			cardView.layer.borderWidth = 0
			cardView.layer.borderColor = nil
			cardView.backgroundColor = .clear
		}
	}

	override func setSelected(_ selected: Bool, animated: Bool) {
		super.setSelected(selected, animated: animated)
		updateSelectionAppearance()
	}

	@objc
	private func didTapMedia(_ recognizer: UITapGestureRecognizer) {
		let location = recognizer.location(in: mediaView)
		if compactOverlay.frame.contains(location) { return }
		if isSelectionMode { return }
		delegate?.mediaBlockCellDidTapMedia(self)
	}
}
