import UIKit

/// Renders an inline "stop" card (title + address + meta) from host-provided strings.
/// Tapping reports the stop's opaque id via `onTap`.
final class StopCardCell: UITableViewCell {
	static let reuseId = "StopCardCell"

	var onTap: ((String) -> Void)?
	var isSelectionMode = false

	private let card = UIView()
	private let pin = UILabel()
	private let titleLabel = UILabel()
	private let subtitleLabel = UILabel()
	private let metaLabel = UILabel()
	private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
	private var stopId = ""

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none
		backgroundColor = .clear
		contentView.backgroundColor = .clear

		card.translatesAutoresizingMaskIntoConstraints = false
		card.layer.cornerRadius = 14
		card.layer.cornerCurve = .continuous
		card.isUserInteractionEnabled = true

		pin.text = "📍"
		pin.font = .systemFont(ofSize: 17)
		pin.translatesAutoresizingMaskIntoConstraints = false
		pin.setContentHuggingPriority(.required, for: .horizontal)

		titleLabel.numberOfLines = 1
		subtitleLabel.numberOfLines = 2
		metaLabel.numberOfLines = 1

		let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, metaLabel])
		textStack.axis = .vertical
		textStack.spacing = 2
		textStack.translatesAutoresizingMaskIntoConstraints = false

		chevron.translatesAutoresizingMaskIntoConstraints = false
		chevron.setContentHuggingPriority(.required, for: .horizontal)
		chevron.contentMode = .scaleAspectFit

		card.addSubview(pin)
		card.addSubview(textStack)
		card.addSubview(chevron)
		contentView.addSubview(card)

		NSLayoutConstraint.activate([
			card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
			card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
			card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
			card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

			pin.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
			pin.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),

			textStack.leadingAnchor.constraint(equalTo: pin.trailingAnchor, constant: 10),
			textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
			textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11),

			chevron.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 8),
			chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
			chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
			chevron.widthAnchor.constraint(equalToConstant: 12)
		])

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
		card.addGestureRecognizer(tap)
	}

	required init?(coder: NSCoder) { fatalError() }

	@objc private func didTap() {
		guard !isSelectionMode else { return }
		onTap?(stopId)
	}

	func configure(_ data: EditorStopData) {
		stopId = data.id
		titleLabel.text = data.title.isEmpty ? "Stop" : data.title
		subtitleLabel.text = data.subtitle
		subtitleLabel.isHidden = data.subtitle.isEmpty
		metaLabel.text = data.meta
		metaLabel.isHidden = data.meta.isEmpty

		let theme = KonuqEditor.theme
		card.backgroundColor = theme.accent.withAlphaComponent(0.10)
		titleLabel.font = UIFont.appSpaceGrotesk(size: 16, weight: .semibold)
		titleLabel.textColor = theme.primaryText
		subtitleLabel.font = UIFont.appDMSans(size: 13, weight: .regular)
		subtitleLabel.textColor = theme.secondaryText
		metaLabel.font = UIFont.appDMSans(size: 12, weight: .regular)
		metaLabel.textColor = theme.secondaryText
		chevron.tintColor = theme.secondaryText.withAlphaComponent(0.6)
	}
}
