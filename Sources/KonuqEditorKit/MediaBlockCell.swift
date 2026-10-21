import UIKit
import Photos
import AVFoundation

protocol MediaBlockCellDelegate: AnyObject {
	func mediaBlockCell(_ cell: MediaBlockCell, didChangeDisplayStyle displayStyle: MediaBlockDisplayStyle)
	/// A photo was tapped: `itemIndex` is its position in the carousel.
	func mediaBlockCell(_ cell: MediaBlockCell, didTapMediaAt itemIndex: Int)
	/// The caption under one photo changed (raw markdown).
	func mediaBlockCell(_ cell: MediaBlockCell, didChangeCaption caption: String, forItemId itemId: String)
	/// The person asked to add photos to this carousel.
	func mediaBlockCellDidRequestAddPhotos(_ cell: MediaBlockCell)
	/// The person removed one photo from the carousel.
	func mediaBlockCell(_ cell: MediaBlockCell, didRemoveItemId itemId: String)
	/// A caption grew or shrank: the row needs a new height.
	func mediaBlockCellDidChangeHeight(_ cell: MediaBlockCell)
}

/// One row of media: a single photo, a swipeable carousel of photos, or a video.
/// Every photo has a caption field under it, italic and muted, that takes markdown.
final class MediaBlockCell: UITableViewCell, BlockSelectableCell, UIScrollViewDelegate, UITextViewDelegate {
	static let reuseId = "MediaBlockCell"

	weak var delegate: MediaBlockCellDelegate?
	private(set) var blockId: String = ""
	private var items: [MediaItem] = []
	private var kind: MediaBlockKind = .image
	private var displayStyle: MediaBlockDisplayStyle = .medium
	private var imageRequestIds: [PHImageRequestID] = []

	private let cardView = UIView()
	private let pager = UIScrollView()
	private let pageControl = UIPageControl()
	private var pages: [MediaPage] = []
	private let compactOverlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
	private let compactStyleButton = UIButton(type: .system)
	/// Photo carousels only: adds more photos from the library, next to the size badge.
	private let addOverlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
	private let addButton = UIButton(type: .system)
	private var mediaHeightConstraint: NSLayoutConstraint?
	private var pageControlHeightConstraint: NSLayoutConstraint?
	private var pageWidthConstraints: [NSLayoutConstraint] = []
	/// Photos shown side by side. One on a phone; on wider screens a page is at most
	/// `preferredPageWidth` wide, so a photo never becomes a thin strip of itself.
	private var columns: Int = 1
	private static let preferredPageWidth: CGFloat = 380

	var isSelectionMode: Bool = false {
		didSet {
			updateSelectionAppearance()
			for page in pages {
				page.caption.isEditable = !isSelectionMode
				page.removeButton.isHidden = (kind != .image) || isSelectionMode
			}
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

		pager.translatesAutoresizingMaskIntoConstraints = false
		// Snapping is done per photo in scrollViewWillEndDragging, since a page may be
		// narrower than the pager on wide screens.
		pager.isPagingEnabled = false
		pager.decelerationRate = .fast
		pager.showsHorizontalScrollIndicator = false
		pager.showsVerticalScrollIndicator = false
		pager.delegate = self
		pager.clipsToBounds = true
		pager.layer.cornerRadius = 16
		cardView.addSubview(pager)

		pageControl.translatesAutoresizingMaskIntoConstraints = false
		pageControl.hidesForSinglePage = true
		pageControl.currentPageIndicatorTintColor = .label
		pageControl.pageIndicatorTintColor = UIColor.label.withAlphaComponent(0.25)
		pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
		cardView.addSubview(pageControl)

		let mediaHeight = pager.heightAnchor.constraint(equalToConstant: 220)
		mediaHeightConstraint = mediaHeight
		let pageControlHeight = pageControl.heightAnchor.constraint(equalToConstant: 0)
		pageControlHeightConstraint = pageControlHeight
		NSLayoutConstraint.activate([
			pager.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
			pager.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
			pager.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
			mediaHeight,
			pageControl.topAnchor.constraint(equalTo: pager.bottomAnchor, constant: 2),
			pageControl.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
			pageControlHeight,
			pageControl.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
		])

		compactOverlay.translatesAutoresizingMaskIntoConstraints = false
		compactOverlay.layer.cornerRadius = 10
		compactOverlay.layer.masksToBounds = true
		cardView.addSubview(compactOverlay)

		compactStyleButton.translatesAutoresizingMaskIntoConstraints = false
		compactStyleButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
		compactStyleButton.showsMenuAsPrimaryAction = true
		compactOverlay.contentView.addSubview(compactStyleButton)

		addOverlay.translatesAutoresizingMaskIntoConstraints = false
		addOverlay.layer.cornerRadius = 10
		addOverlay.layer.masksToBounds = true
		cardView.addSubview(addOverlay)

		addButton.translatesAutoresizingMaskIntoConstraints = false
		addButton.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
		addButton.accessibilityLabel = L.t("editor.media.add_photos")
		addButton.addTarget(self, action: #selector(didTapAddPhotos), for: .touchUpInside)
		addOverlay.contentView.addSubview(addButton)

		NSLayoutConstraint.activate([
			compactOverlay.topAnchor.constraint(equalTo: pager.topAnchor, constant: 8),
			compactOverlay.trailingAnchor.constraint(equalTo: pager.trailingAnchor, constant: -8),
			compactOverlay.heightAnchor.constraint(equalToConstant: 32),
			compactOverlay.widthAnchor.constraint(equalTo: compactOverlay.heightAnchor),

			addOverlay.topAnchor.constraint(equalTo: compactOverlay.topAnchor),
			addOverlay.trailingAnchor.constraint(equalTo: compactOverlay.leadingAnchor, constant: -6),
			addOverlay.heightAnchor.constraint(equalTo: compactOverlay.heightAnchor),
			addOverlay.widthAnchor.constraint(equalTo: compactOverlay.heightAnchor),

			addButton.topAnchor.constraint(equalTo: addOverlay.contentView.topAnchor),
			addButton.bottomAnchor.constraint(equalTo: addOverlay.contentView.bottomAnchor),
			addButton.leadingAnchor.constraint(equalTo: addOverlay.contentView.leadingAnchor),
			addButton.trailingAnchor.constraint(equalTo: addOverlay.contentView.trailingAnchor),

			compactStyleButton.topAnchor.constraint(equalTo: compactOverlay.contentView.topAnchor),
			compactStyleButton.bottomAnchor.constraint(equalTo: compactOverlay.contentView.bottomAnchor),
			compactStyleButton.leadingAnchor.constraint(equalTo: compactOverlay.contentView.leadingAnchor),
			compactStyleButton.trailingAnchor.constraint(equalTo: compactOverlay.contentView.trailingAnchor),
		])

		updateSelectionAppearance()
		updateCompactStyleTitle()
		compactStyleButton.menu = makeStyleMenu()
	}

	required init?(coder: NSCoder) {
		fatalError()
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		for id in imageRequestIds { PHImageManager.default().cancelImageRequest(id) }
		imageRequestIds = []
		for page in pages { page.removeFromSuperview() }
		pages = []
	}

	func configure(blockId: String, kind: MediaBlockKind, items: [MediaItem], displayStyle: MediaBlockDisplayStyle) {
		self.blockId = blockId
		self.kind = kind
		self.items = items
		self.displayStyle = displayStyle

		rebuildPages()
		updateCompactStyleTitle()
		compactStyleButton.menu = makeStyleMenu()
		addOverlay.isHidden = kind != .image
		updateHeight()
		updateSelectionAppearance()
	}

	@objc
	private func didTapRemovePhoto(_ sender: UIButton) {
		guard !isSelectionMode, sender.tag >= 0, sender.tag < items.count else { return }
		delegate?.mediaBlockCell(self, didRemoveItemId: items[sender.tag].id)
	}

	@objc
	private func didTapAddPhotos() {
		guard !isSelectionMode else { return }
		delegate?.mediaBlockCellDidRequestAddPhotos(self)
	}

	/// The width of one photo page for the current pager width.
	private var itemWidth: CGFloat {
		max(1, pager.bounds.width / CGFloat(max(1, columns)))
	}

	/// How many photos sit side by side at this width: one on a phone, two on an iPad,
	/// three on the widest layouts. A single photo always spans the row.
	private func columns(for width: CGFloat) -> Int {
		guard items.count > 1 else { return 1 }
		let fit = Int((width / Self.preferredPageWidth).rounded(.down))
		return max(1, min(3, fit))
	}

	/// How many positions the carousel can stop at: one when every photo is on screen.
	private var scrollPositions: Int {
		max(1, items.count - columns + 1)
	}

	private func updatePageControl() {
		pageControl.numberOfPages = scrollPositions
		pageControl.currentPage = min(currentItemIndex, scrollPositions - 1)
	}

	/// The index of the photo currently in view (the leftmost one when several show).
	var currentItemIndex: Int {
		guard pager.bounds.width > 0 else { return 0 }
		return max(0, min(items.count - 1, Int((pager.contentOffset.x + itemWidth / 2) / itemWidth)))
	}

	/// The pager's width before its own layout pass: the cell width minus the card
	/// and pager insets. The cell's bounds are already right inside layoutSubviews.
	private var expectedPagerWidth: CGFloat {
		max(0, bounds.width - 48)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let wanted = columns(for: expectedPagerWidth)
		if wanted != columns {
			columns = wanted
			applyPageWidths()
			updateHeight()
			updatePageControl()
		}
	}

	private func applyPageWidths() {
		NSLayoutConstraint.deactivate(pageWidthConstraints)
		pageWidthConstraints = pages.map {
			$0.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor, multiplier: 1 / CGFloat(max(1, columns)))
		}
		NSLayoutConstraint.activate(pageWidthConstraints)
	}

	// MARK: Pages

	private func rebuildPages() {
		for page in pages { page.removeFromSuperview() }
		pages = []
		for (index, item) in items.enumerated() {
			let page = MediaPage()
			page.translatesAutoresizingMaskIntoConstraints = false
			page.image.isUserInteractionEnabled = true
			page.image.tag = index
			page.caption.delegate = self
			page.caption.tag = index
			page.caption.isEditable = !isSelectionMode
			page.setCaption(item.caption, placeholder: L.t("editor.media.caption.placeholder"))
			page.playIcon.isHidden = (kind == .image)
			page.removeButton.isHidden = (kind != .image) || isSelectionMode
			page.removeButton.tag = index
			page.removeButton.addTarget(self, action: #selector(didTapRemovePhoto(_:)), for: .touchUpInside)
			let tap = UITapGestureRecognizer(target: self, action: #selector(didTapMedia(_:)))
			page.image.addGestureRecognizer(tap)
			if kind == .image {
				page.image.addInteraction(UIContextMenuInteraction(delegate: self))
			}
			pager.addSubview(page)
			pages.append(page)
			loadMedia(for: item, into: page)
		}
		columns = columns(for: expectedPagerWidth)
		layoutPages()
		updatePageControl()
		pageControlHeightConstraint?.constant = items.count > 1 ? 16 : 0
		pager.setContentOffset(.zero, animated: false)
	}

	/// Pages are fresh views each rebuild, so only the pager-side constraints are added here.
	private func layoutPages() {
		var previous: MediaPage?
		for page in pages {
			NSLayoutConstraint.activate([
				page.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
				page.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
				page.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor),
				page.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? pager.contentLayoutGuide.leadingAnchor),
			])
			previous = page
		}
		if let previous {
			previous.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor).isActive = true
		}
		applyPageWidths()
	}

	/// The media height from the chosen size, plus the tallest caption below it.
	private func updateHeight() {
		let imageHeight: CGFloat = {
			switch displayStyle {
			case .small: 140
			case .medium: 220
			case .large: 320
			}
		}()
		let fullWidth = max(200, (superview?.bounds.width ?? UIScreen.main.bounds.width) - 48)
		let width = fullWidth / CGFloat(max(1, columns))
		let captionHeight = pages.map { $0.captionHeight(for: width) }.max() ?? MediaPage.minimumCaptionHeight
		for page in pages {
			page.setImageHeight(imageHeight)
			page.setImageInset(columns > 1 ? 4 : 0)
		}
		mediaHeightConstraint?.constant = imageHeight + captionHeight
	}

	// MARK: Style menu

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
		let actionSmall = UIAction(title: L.t("editor.media.small"), state: displayStyle == .small ? .on : .off) { [weak self] _ in
			self?.applyDisplayStyle(.small)
		}
		let actionMedium = UIAction(title: L.t("editor.media.medium"), state: displayStyle == .medium ? .on : .off) { [weak self] _ in
			self?.applyDisplayStyle(.medium)
		}
		let actionLarge = UIAction(title: L.t("editor.media.large"), state: displayStyle == .large ? .on : .off) { [weak self] _ in
			self?.applyDisplayStyle(.large)
		}
		var children: [UIMenuElement] = [actionSmall, actionMedium, actionLarge]
		if kind == .image {
			let addPhotos = UIAction(title: L.t("editor.media.add_photos"), image: UIImage(systemName: "photo.badge.plus")) { [weak self] _ in
				guard let self else { return }
				self.delegate?.mediaBlockCellDidRequestAddPhotos(self)
			}
			children.append(UIMenu(options: .displayInline, children: [addPhotos]))
		}
		return UIMenu(children: children)
	}

	private func applyDisplayStyle(_ newStyle: MediaBlockDisplayStyle) {
		displayStyle = newStyle
		updateCompactStyleTitle()
		compactStyleButton.menu = makeStyleMenu()
		updateHeight()
		delegate?.mediaBlockCell(self, didChangeDisplayStyle: newStyle)
	}

	// MARK: Loading

	private func loadMedia(for item: MediaItem, into page: MediaPage) {
		let reference = item.reference
		if reference.hasPrefix("phasset:") {
			let id = String(reference.dropFirst("phasset:".count))
			let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
			guard let asset = assets.firstObject else { return }
			let options = PHImageRequestOptions()
			options.isNetworkAccessAllowed = true
			options.resizeMode = .fast
			options.deliveryMode = .opportunistic
			let requestId = PHImageManager.default().requestImage(
				for: asset,
				targetSize: CGSize(width: 1200, height: 1200),
				contentMode: .aspectFill,
				options: options
			) { [weak page] image, _ in
				DispatchQueue.main.async { page?.image.image = image }
			}
			imageRequestIds.append(requestId)
			return
		}

		guard let url = MediaReferenceResolver.localFileURL(from: reference) else { return }
		if kind == .image {
			DispatchQueue.global(qos: .userInitiated).async { [weak page] in
				guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
				DispatchQueue.main.async { page?.image.image = image }
			}
			return
		}
		DispatchQueue.global(qos: .userInitiated).async { [weak page] in
			let asset = AVAsset(url: url)
			let generator = AVAssetImageGenerator(asset: asset)
			generator.appliesPreferredTrackTransform = true
			generator.maximumSize = CGSize(width: 1200, height: 1200)
			let image: UIImage? = {
				let time = CMTime(seconds: 0.2, preferredTimescale: 600)
				guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
				return UIImage(cgImage: cgImage)
			}()
			DispatchQueue.main.async { page?.image.image = image ?? UIImage(systemName: "video") }
		}
	}

	// MARK: Selection

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

	// MARK: Interaction

	@objc
	private func didTapMedia(_ recognizer: UITapGestureRecognizer) {
		guard let image = recognizer.view else { return }
		let location = recognizer.location(in: cardView)
		if compactOverlay.frame.contains(location) || addOverlay.frame.contains(location) { return }
		if isSelectionMode { return }
		delegate?.mediaBlockCell(self, didTapMediaAt: image.tag)
	}

	private var maxContentOffsetX: CGFloat {
		max(0, pager.contentSize.width - pager.bounds.width)
	}

	@objc
	private func pageControlChanged() {
		let x = min(maxContentOffsetX, CGFloat(pageControl.currentPage) * itemWidth)
		pager.setContentOffset(CGPoint(x: x, y: 0), animated: true)
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView === pager, pager.bounds.width > 0 else { return }
		pageControl.currentPage = min(currentItemIndex, scrollPositions - 1)
	}

	/// Snap so a photo's left edge lines up with the pager, whatever the page width.
	func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
		guard scrollView === pager, items.count > 1 else { return }
		let width = itemWidth
		var index = scrollView.contentOffset.x / width
		if velocity.x > 0.3 { index = index.rounded(.up) }
		else if velocity.x < -0.3 { index = index.rounded(.down) }
		else { index = index.rounded() }
		let x = min(maxContentOffsetX, max(0, index * width))
		targetContentOffset.pointee = CGPoint(x: x, y: 0)
	}

	// MARK: Captions

	func textViewDidChange(_ textView: UITextView) {
		let index = textView.tag
		guard index >= 0, index < items.count, index < pages.count else { return }
		pages[index].refreshPlaceholder()
		items[index].caption = textView.text
		delegate?.mediaBlockCell(self, didChangeCaption: textView.text, forItemId: items[index].id)
		let before = mediaHeightConstraint?.constant ?? 0
		updateHeight()
		if before != mediaHeightConstraint?.constant {
			delegate?.mediaBlockCellDidChangeHeight(self)
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		pages[safe: textView.tag]?.refreshPlaceholder()
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		pages[safe: textView.tag]?.refreshPlaceholder()
	}
}

// MARK: - Context menu on a photo

extension MediaBlockCell: UIContextMenuInteractionDelegate {
	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
		guard !isSelectionMode, let index = (interaction.view as? UIImageView)?.tag, index < items.count else { return nil }
		let itemId = items[index].id
		return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
			guard let self else { return nil }
			var actions: [UIAction] = [
				UIAction(title: L.t("editor.media.add_photos"), image: UIImage(systemName: "photo.badge.plus")) { [weak self] _ in
					guard let self else { return }
					self.delegate?.mediaBlockCellDidRequestAddPhotos(self)
				}
			]
			actions.append(UIAction(title: L.t("editor.media.remove_photo"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
				guard let self else { return }
				self.delegate?.mediaBlockCell(self, didRemoveItemId: itemId)
			})
			return UIMenu(children: actions)
		}
	}
}

// MARK: - One page: the photo and its caption

private final class MediaPage: UIView {
	static let minimumCaptionHeight: CGFloat = 30

	let image = UIImageView()
	let caption = UITextView()
	let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
	/// Top-left of the photo: takes this photo out of the carousel.
	let removeButton = UIButton(type: .system)
	private let removeBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
	private let placeholder = UILabel()
	private var imageHeightConstraint: NSLayoutConstraint?
	private var imageLeadingConstraint: NSLayoutConstraint?
	private var imageTrailingConstraint: NSLayoutConstraint?

	/// The photo's height comes from the block's size setting; the caption takes the rest.
	func setImageHeight(_ height: CGFloat) {
		imageHeightConstraint?.constant = height
	}

	/// A little air between photos when several share the row.
	func setImageInset(_ inset: CGFloat) {
		imageLeadingConstraint?.constant = inset
		imageTrailingConstraint?.constant = -inset
	}

	static var captionFont: UIFont {
		let base = UIFont.preferredFont(forTextStyle: .footnote)
		let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) ?? base.fontDescriptor
		return UIFont(descriptor: descriptor, size: base.pointSize)
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		image.translatesAutoresizingMaskIntoConstraints = false
		image.contentMode = .scaleAspectFill
		image.clipsToBounds = true
		image.layer.cornerRadius = 16
		image.layer.masksToBounds = true
		image.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.8)
		addSubview(image)

		caption.translatesAutoresizingMaskIntoConstraints = false
		caption.isScrollEnabled = false
		caption.backgroundColor = .clear
		caption.font = Self.captionFont
		caption.textColor = .secondaryLabel
		caption.textAlignment = .center
		caption.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 4, right: 8)
		caption.textContainer.lineFragmentPadding = 0
		caption.returnKeyType = .done
		addSubview(caption)

		placeholder.translatesAutoresizingMaskIntoConstraints = false
		placeholder.font = Self.captionFont
		placeholder.textColor = UIColor.tertiaryLabel
		placeholder.textAlignment = .center
		placeholder.isUserInteractionEnabled = false
		addSubview(placeholder)

		playIcon.translatesAutoresizingMaskIntoConstraints = false
		playIcon.contentMode = .center
		playIcon.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
		playIcon.tintColor = .white
		playIcon.backgroundColor = UIColor.black.withAlphaComponent(0.35)
		playIcon.layer.cornerRadius = 18
		playIcon.layer.masksToBounds = true
		image.addSubview(playIcon)

		removeBackground.translatesAutoresizingMaskIntoConstraints = false
		removeBackground.layer.cornerRadius = 14
		removeBackground.layer.masksToBounds = true
		removeBackground.isUserInteractionEnabled = false
		addSubview(removeBackground)
		removeButton.translatesAutoresizingMaskIntoConstraints = false
		removeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
		removeButton.tintColor = .label
		addSubview(removeButton)

		let imageHeight = image.heightAnchor.constraint(equalToConstant: 220)
		imageHeightConstraint = imageHeight
		let imageLeading = image.leadingAnchor.constraint(equalTo: leadingAnchor)
		let imageTrailing = image.trailingAnchor.constraint(equalTo: trailingAnchor)
		imageLeadingConstraint = imageLeading
		imageTrailingConstraint = imageTrailing
		NSLayoutConstraint.activate([
			imageHeight,
			image.topAnchor.constraint(equalTo: topAnchor),
			imageLeading,
			imageTrailing,
			caption.topAnchor.constraint(equalTo: image.bottomAnchor),
			caption.leadingAnchor.constraint(equalTo: leadingAnchor),
			caption.trailingAnchor.constraint(equalTo: trailingAnchor),
			caption.bottomAnchor.constraint(equalTo: bottomAnchor),
			caption.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumCaptionHeight),
			placeholder.centerYAnchor.constraint(equalTo: caption.centerYAnchor),
			placeholder.leadingAnchor.constraint(equalTo: caption.leadingAnchor, constant: 8),
			placeholder.trailingAnchor.constraint(equalTo: caption.trailingAnchor, constant: -8),
			playIcon.centerXAnchor.constraint(equalTo: image.centerXAnchor),
			playIcon.centerYAnchor.constraint(equalTo: image.centerYAnchor),
			playIcon.widthAnchor.constraint(equalToConstant: 36),
			playIcon.heightAnchor.constraint(equalToConstant: 36),
			removeButton.topAnchor.constraint(equalTo: image.topAnchor, constant: 8),
			removeButton.leadingAnchor.constraint(equalTo: image.leadingAnchor, constant: 8),
			removeButton.widthAnchor.constraint(equalToConstant: 28),
			removeButton.heightAnchor.constraint(equalToConstant: 28),
			removeBackground.topAnchor.constraint(equalTo: removeButton.topAnchor),
			removeBackground.bottomAnchor.constraint(equalTo: removeButton.bottomAnchor),
			removeBackground.leadingAnchor.constraint(equalTo: removeButton.leadingAnchor),
			removeBackground.trailingAnchor.constraint(equalTo: removeButton.trailingAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError() }

	func setCaption(_ text: String, placeholder text2: String) {
		caption.text = text
		placeholder.text = text2
		refreshPlaceholder()
	}

	func refreshPlaceholder() {
		placeholder.isHidden = !(caption.text ?? "").isEmpty
	}

	func captionHeight(for width: CGFloat) -> CGFloat {
		let size = caption.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
		return max(Self.minimumCaptionHeight, ceil(size.height))
	}
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
