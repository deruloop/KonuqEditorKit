import UIKit

final class SelectionActionBarView: UIView {
    let deleteButton = UIButton(type: .system)
    let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.layer.cornerRadius = 14
        blur.layer.masksToBounds = true
        
        addSubview(blur)
        blur.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel
        
        deleteButton.setTitle(String(localized: "note.editor.overlay.delete"), for: .normal)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        deleteButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        deleteButton.isEnabled = false
        
        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), deleteButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        
        blur.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor)
        ])
        
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(selectedCount: Int) {
        if selectedCount == 1 {
            titleLabel.text = String(localized: "note.editor.overlay.selected.one")
        } else {
            let format = String(localized: "note.editor.overlay.selected.many")
            titleLabel.text = String(format: format, selectedCount)
        }
        deleteButton.isEnabled = selectedCount > 0
        deleteButton.alpha = selectedCount > 0 ? 1 : 0.4
    }
}
