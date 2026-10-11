import UIKit
import ComicCore

@MainActor
final class BookshelfResumeView: UIControl {
    private let cover = RemoteImageView()
    private let heading = UILabel()
    private let position = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true; accessibilityTraits = .button
        accessibilityIdentifier = "bookshelf.resume"; accessibilityLabel = "继续阅读"
        cover.contentMode = .scaleAspectFill; cover.clipsToBounds = true; cover.layer.cornerRadius = 17
        heading.font = .systemFont(ofSize: 15, weight: .bold); heading.textColor = Palette.text
        heading.lineBreakMode = .byTruncatingTail
        position.font = .systemFont(ofSize: 12); position.textColor = Palette.text3
        let copy = UIStackView(arrangedSubviews: [heading, position]); copy.axis = .vertical; copy.spacing = 2
        let action = UILabel(); action.text = "续读 ›"; action.font = .systemFont(ofSize: 12, weight: .bold); action.textColor = Palette.accent
        action.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [cover, copy, action]); row.spacing = 10; row.alignment = .center
        row.isUserInteractionEnabled = false; row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        let top = UIView(), bottom = UIView()
        for line in [top, bottom] {
            line.backgroundColor = Palette.borderSoft; line.translatesAutoresizingMaskIntoConstraints = false; addSubview(line)
            line.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            line.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52), top.topAnchor.constraint(equalTo: topAnchor), bottom.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            row.centerYAnchor.constraint(equalTo: centerYAnchor), cover.widthAnchor.constraint(equalToConstant: 34), cover.heightAnchor.constraint(equalToConstant: 34)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(comic: ComicSummary, chapterIndex: Int, environment: AppEnvironment) {
        heading.text = comic.title; position.text = "上次看到 · 第 \(chapterIndex + 1) 话"
        accessibilityValue = comic.title + "，" + (position.text ?? "")
        cover.loadCover(comic, referer: environment.source(for: comic)?.referer ?? "", library: environment.localLibrary)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cover.cancel() }
    }
}
