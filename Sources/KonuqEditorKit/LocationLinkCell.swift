import UIKit

/// Renders a generic "location link": a pin icon followed by a label, styled as a link.
/// Tapping reports the destination `url` via `onTap`.
final class LocationLinkCell: UITableViewCell {
	static let reuseId = "LocationLinkCell"

	var onTap: ((URL) -> Void)?
	var isSelectionMode = false

	private let container = UIView()
	private let pin = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
	private let label = UILabel()
	private var url: URL?

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none
		backgroundColor = .clear
		contentView.backgroundColor = .clear

		container.translatesAutoresizingMaskIntoConstraints = false
		container.isUserInteractionEnabled = true

		pin.translatesAutoresizingMaskIntoConstraints = false
		pin.contentMode = .scaleAspectFit
		pin.setContentHuggingPriority(.required, for: .horizontal)
		pin.setContentCompressionResistancePriority(.required, for: .horizontal)

		label.numberOfLines = 2
		label.translatesAutoresizingMaskIntoConstraints = false

		container.addSubview(pin)
		container.addSubview(label)
		contentView.addSubview(container)

		NSLayoutConstraint.activate([
			container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
			container.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -4),
			container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
			container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

			pin.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			pin.centerYAnchor.constraint(equalTo: label.centerYAnchor),
			pin.widthAnchor.constraint(equalToConstant: 18),
			pin.heightAnchor.constraint(equalToConstant: 18),

			label.leadingAnchor.constraint(equalTo: pin.trailingAnchor, constant: 7),
			label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
			label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
		])

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
		container.addGestureRecognizer(tap)
	}

	required init?(coder: NSCoder) { fatalError() }

	@objc private func didTap() {
		guard !isSelectionMode, let url else { return }
		onTap?(url)
	}

	func configure(_ data: EditorLocationData) {
		url = URL(string: data.url)
		let theme = KonuqEditor.theme
		let text = data.label.isEmpty ? "Location" : data.label
		label.attributedText = NSAttributedString(
			string: text,
			attributes: [
				.font: UIFont.appDMSans(size: 16, weight: .medium),
				.foregroundColor: theme.accent,
				.underlineStyle: NSUnderlineStyle.single.rawValue,
				.underlineColor: theme.accent.withAlphaComponent(0.4)
			]
		)
		pin.tintColor = theme.accent
	}
}
