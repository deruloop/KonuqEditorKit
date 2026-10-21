import UIKit

/// One photo of a carousel shown full screen, with its caption.
struct FullScreenGalleryItem {
	var reference: String
	/// Plain text: markdown markers already stripped.
	var caption: String
}

/// The photos of one carousel, full screen on black. Swiping sideways moves to the next
/// photo, each shown with its caption at the bottom; a tap or a downward drag closes it.
final class FullScreenGalleryViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
	private let items: [FullScreenGalleryItem]
	private let startIndex: Int
	private let loadImage: (String, @escaping (UIImage?) -> Void) -> Void

	private let pager = UIScrollView()
	private let pageControl = UIPageControl()
	private var pages: [Page] = []
	private var loaded: Set<Int> = []
	private var didScrollToStart = false

	private var isDismissingInteractively = false
	private let dismissDistance: CGFloat = 140
	private let dismissVelocity: CGFloat = 900

	init(items: [FullScreenGalleryItem], startIndex: Int, loadImage: @escaping (String, @escaping (UIImage?) -> Void) -> Void) {
		self.items = items
		self.startIndex = max(0, min(items.count - 1, startIndex))
		self.loadImage = loadImage
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError() }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		view.window?.endEditing(true)
		view.endEditing(true)
		UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .black

		pager.translatesAutoresizingMaskIntoConstraints = false
		pager.isPagingEnabled = true
		pager.showsHorizontalScrollIndicator = false
		pager.showsVerticalScrollIndicator = false
		pager.alwaysBounceVertical = false
		pager.delegate = self
		pager.contentInsetAdjustmentBehavior = .never
		view.addSubview(pager)
		NSLayoutConstraint.activate([
			pager.topAnchor.constraint(equalTo: view.topAnchor),
			pager.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),
		])

		var previous: Page?
		for item in items {
			let page = Page()
			page.translatesAutoresizingMaskIntoConstraints = false
			page.setCaption(item.caption)
			pager.addSubview(page)
			NSLayoutConstraint.activate([
				page.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
				page.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
				page.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor),
				page.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor),
				page.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? pager.contentLayoutGuide.leadingAnchor),
			])
			pages.append(page)
			previous = page
		}
		previous?.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor).isActive = true

		pageControl.translatesAutoresizingMaskIntoConstraints = false
		pageControl.numberOfPages = items.count
		pageControl.currentPage = startIndex
		pageControl.hidesForSinglePage = true
		pageControl.currentPageIndicatorTintColor = .white
		pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.35)
		pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
		view.addSubview(pageControl)
		NSLayoutConstraint.activate([
			pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
		])

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTapToDismiss))
		view.addGestureRecognizer(tap)

		// Vertical drags close the viewer; sideways ones belong to the pager.
		let pan = UIPanGestureRecognizer(target: self, action: #selector(didPanToDismiss(_:)))
		pan.delegate = self
		view.addGestureRecognizer(pan)

		loadAround(startIndex)
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if !didScrollToStart, pager.bounds.width > 0 {
			didScrollToStart = true
			pager.setContentOffset(CGPoint(x: CGFloat(startIndex) * pager.bounds.width, y: 0), animated: false)
		}
	}

	override var prefersStatusBarHidden: Bool { true }

	private var currentIndex: Int {
		guard pager.bounds.width > 0 else { return startIndex }
		return max(0, min(items.count - 1, Int((pager.contentOffset.x + pager.bounds.width / 2) / pager.bounds.width)))
	}

	/// Full-size images are heavy: the one on screen and its neighbours load, the rest wait.
	private func loadAround(_ index: Int) {
		for i in max(0, index - 1)...min(items.count - 1, index + 1) where !loaded.contains(i) {
			loaded.insert(i)
			let page = pages[i]
			loadImage(items[i].reference) { [weak page] image in
				page?.imageView.image = image
			}
		}
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView === pager else { return }
		let index = currentIndex
		pageControl.currentPage = index
		loadAround(index)
	}

	@objc
	private func pageControlChanged() {
		pager.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * pager.bounds.width, y: 0), animated: true)
	}

	@objc
	private func didTapToDismiss() {
		dismiss(animated: true)
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
		let velocity = pan.velocity(in: view)
		return abs(velocity.y) > abs(velocity.x) && velocity.y > 0
	}

	@objc
	private func didPanToDismiss(_ recognizer: UIPanGestureRecognizer) {
		let translation = recognizer.translation(in: view)
		let y = max(translation.y, 0)
		let progress = min(y / max(dismissDistance, 1), 1)
		let scale = 1 - (progress * 0.06)

		switch recognizer.state {
		case .began:
			isDismissingInteractively = true
		case .changed:
			guard isDismissingInteractively else { return }
			pager.transform = CGAffineTransform(translationX: 0, y: y).scaledBy(x: scale, y: scale)
			view.backgroundColor = UIColor.black.withAlphaComponent(1 - progress)
			pageControl.alpha = 1 - progress
		case .ended, .cancelled:
			guard isDismissingInteractively else { return }
			isDismissingInteractively = false
			let velocity = recognizer.velocity(in: view)
			if y > dismissDistance || velocity.y > dismissVelocity {
				UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) { [weak self] in
					guard let self else { return }
					self.pager.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
					self.view.backgroundColor = UIColor.black.withAlphaComponent(0)
				} completion: { [weak self] _ in
					self?.dismiss(animated: false)
				}
			} else {
				UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) { [weak self] in
					guard let self else { return }
					self.pager.transform = .identity
					self.view.backgroundColor = .black
					self.pageControl.alpha = 1
				}
			}
		default:
			break
		}
	}

	/// One photo on black with its caption pinned near the bottom.
	private final class Page: UIView {
		let imageView = UIImageView()
		private let caption = UILabel()
		private let captionBackground = UIView()

		override init(frame: CGRect) {
			super.init(frame: frame)
			imageView.translatesAutoresizingMaskIntoConstraints = false
			imageView.contentMode = .scaleAspectFit
			addSubview(imageView)

			captionBackground.translatesAutoresizingMaskIntoConstraints = false
			captionBackground.backgroundColor = UIColor.black.withAlphaComponent(0.55)
			captionBackground.layer.cornerRadius = 12
			addSubview(captionBackground)

			caption.translatesAutoresizingMaskIntoConstraints = false
			caption.numberOfLines = 0
			caption.textAlignment = .center
			caption.textColor = UIColor.white.withAlphaComponent(0.92)
			let base = UIFont.preferredFont(forTextStyle: .subheadline)
			caption.font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitItalic) ?? base.fontDescriptor, size: base.pointSize)
			captionBackground.addSubview(caption)

			NSLayoutConstraint.activate([
				imageView.topAnchor.constraint(equalTo: topAnchor),
				imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
				imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
				imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
				captionBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
				captionBackground.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -36),
				captionBackground.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
				captionBackground.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
				caption.topAnchor.constraint(equalTo: captionBackground.topAnchor, constant: 8),
				caption.bottomAnchor.constraint(equalTo: captionBackground.bottomAnchor, constant: -8),
				caption.leadingAnchor.constraint(equalTo: captionBackground.leadingAnchor, constant: 14),
				caption.trailingAnchor.constraint(equalTo: captionBackground.trailingAnchor, constant: -14),
			])
		}

		required init?(coder: NSCoder) { fatalError() }

		func setCaption(_ text: String) {
			caption.text = text
			captionBackground.isHidden = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}
	}
}
