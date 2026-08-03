import UIKit

/// Renders an inline "day" divider (a labelled rule) from a host-provided title.
final class DayDividerCell: UITableViewCell {
	static let reuseId = "DayDividerCell"

	private let label = UILabel()
	private let line = UIView()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none
		backgroundColor = .clear
		contentView.backgroundColor = .clear

		label.translatesAutoresizingMaskIntoConstraints = false
		label.setContentHuggingPriority(.required, for: .horizontal)
		label.setContentCompressionResistancePriority(.required, for: .horizontal)

		line.translatesAutoresizingMaskIntoConstraints = false

		contentView.addSubview(label)
		contentView.addSubview(line)

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
			label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
			label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

			line.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
			line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
			line.centerYAnchor.constraint(equalTo: label.centerYAnchor),
			line.heightAnchor.constraint(equalToConstant: 1)
		])
	}

	required init?(coder: NSCoder) { fatalError() }

	func configure(title: String) {
		let theme = KonuqEditor.theme
		label.text = title.uppercased()
		label.font = UIFont.appSpaceGrotesk(size: 12, weight: .bold)
		label.textColor = theme.secondaryText
		label.attributedText = NSAttributedString(
			string: title.uppercased(),
			attributes: [
				.font: UIFont.appSpaceGrotesk(size: 12, weight: .bold),
				.foregroundColor: theme.secondaryText,
				.kern: 1.2
			]
		)
		line.backgroundColor = theme.secondaryText.withAlphaComponent(0.25)
	}
}
