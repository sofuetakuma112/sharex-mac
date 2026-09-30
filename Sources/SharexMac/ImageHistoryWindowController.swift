import AppKit
import ImageIO

struct HistoryImage {
    let url: URL
    let date: Date
}

final class ImageHistoryWindowController: NSWindowController, NSWindowDelegate, NSCollectionViewDataSource, NSSearchFieldDelegate {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "bmp", "webp"]

    private let settings = Settings.shared
    private let thumbnails = ThumbnailCache()
    private let collectionView = HistoryCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private let searchField = NSSearchField()
    private let sizeSlider = NSSlider(value: 160, minValue: 80, maxValue: 320, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private var allImages: [HistoryImage] = []
    private var images: [HistoryImage] = []
    private var scanGeneration = 0
    private var thumbnailPixelSize = 0

    init() {
        let window = HistoryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localized("Image History")
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("ImageHistoryWindow") {
            window.center()
        }
        window.setFrameAutosaveName("ImageHistoryWindow")
        super.init(window: window)
        window.delegate = self
        setUpContent()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(collectionView)
        reload()
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        reload()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reload()
    }

    private func setUpContent() {
        guard let contentView = window?.contentView else { return }

        searchField.placeholderString = localized("Filter by file name")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true

        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        sizeSlider.doubleValue = settings.thumbnailSize
        sizeSlider.target = self
        sizeSlider.action = #selector(thumbnailSizeChanged)
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        sizeSlider.toolTip = localized("Thumbnail size")

        let smallIcon = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage())
        smallIcon.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        smallIcon.contentTintColor = .secondaryLabelColor
        let largeIcon = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage())
        largeIcon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        largeIcon.contentTintColor = .secondaryLabelColor

        let bar = NSStackView(views: [searchField, countLabel, smallIcon, sizeSlider, largeIcon])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        bar.setCustomSpacing(16, after: countLabel)
        bar.setCustomSpacing(4, after: smallIcon)
        bar.setCustomSpacing(4, after: sizeSlider)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        updateItemSize()

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.textBackgroundColor]
        collectionView.register(HistoryItem.self, forItemWithIdentifier: HistoryItem.identifier)
        collectionView.onOpen = { [weak self] in self?.openSelected() }
        collectionView.onCopy = { [weak self] in self?.copyImage() }
        collectionView.onTrash = { [weak self] in self?.trashSelected() }
        collectionView.contextMenu = { [weak self] in self?.makeContextMenu() }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(bar)
        contentView.addSubview(separator)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: contentView.topAnchor),
            bar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func reload() {
        scanGeneration += 1
        let generation = scanGeneration
        let folder = settings.screenshotsFolder
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = Self.scan(folder)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == scanGeneration else { return }
                allImages = scanned
                applyFilter()
            }
        }
    }

    private static func scan(_ folder: URL) -> [HistoryImage] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        var result: [HistoryImage] = []
        for case let url as URL in enumerator where imageExtensions.contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result.append(HistoryImage(url: url, date: values.creationDate ?? values.contentModificationDate ?? .distantPast))
        }
        return result.sorted { $0.date > $1.date }
    }

    private func applyFilter() {
        let selectedURLs = Set(selectedImages.map(\.url))
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        images = query.isEmpty ? allImages : allImages.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
        collectionView.reloadData()
        collectionView.selectionIndexPaths = Set(images.indices.filter { selectedURLs.contains(images[$0].url) }.map { IndexPath(item: $0, section: 0) })

        countLabel.stringValue = query.isEmpty ? localized("%d items", allImages.count) : localized("%1$d of %2$d items", images.count, allImages.count)
        emptyLabel.stringValue = allImages.isEmpty ? localized("No captures yet") : localized("No matching images")
        emptyLabel.isHidden = !images.isEmpty
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    @objc private func thumbnailSizeChanged() {
        settings.thumbnailSize = sizeSlider.doubleValue
        let previousPixelSize = thumbnailPixelSize
        updateItemSize()
        if thumbnailPixelSize != previousPixelSize {
            let selection = collectionView.selectionIndexPaths
            collectionView.reloadData()
            collectionView.selectionIndexPaths = selection
        }
    }

    private func updateItemSize() {
        let size = CGFloat(settings.thumbnailSize)
        layout.itemSize = NSSize(width: size, height: size + HistoryItem.labelHeight)
        layout.invalidateLayout()
        let scale = window?.backingScaleFactor ?? 2
        thumbnailPixelSize = Int((size * scale / 128).rounded(.up)) * 128
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        images.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: HistoryItem.identifier, for: indexPath)
        guard let historyItem = item as? HistoryItem else { return item }
        let image = images[indexPath.item]
        historyItem.configure(url: image.url, toolTip: "\(image.url.path)\n\(dateFormatter.string(from: image.date))")
        historyItem.isSelected = collectionView.selectionIndexPaths.contains(indexPath)
        thumbnails.thumbnail(for: image.url, maxPixelSize: thumbnailPixelSize) { [weak historyItem] thumbnail in
            historyItem?.setThumbnail(thumbnail, for: image.url)
        }
        return historyItem
    }

    private var selectedImages: [HistoryImage] {
        collectionView.selectionIndexPaths
            .sorted()
            .compactMap { images.indices.contains($0.item) ? images[$0.item] : nil }
    }

    private func makeContextMenu() -> NSMenu? {
        let selection = selectedImages
        guard !selection.isEmpty else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: localized("Open"), action: #selector(openSelected), keyEquivalent: "")
        menu.addItem(withTitle: localized("Show in Finder"), action: #selector(revealSelected), keyEquivalent: "")
        menu.addItem(.separator())
        let copyItem = menu.addItem(withTitle: localized("Copy Image"), action: #selector(copyImage), keyEquivalent: "")
        copyItem.isEnabled = selection.count == 1
        menu.addItem(withTitle: localized("Copy File Path"), action: #selector(copyPaths), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: localized("Move to Trash"), action: #selector(trashSelected), keyEquivalent: "")
        menu.autoenablesItems = false
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func openSelected() {
        selectedImages.forEach { NSWorkspace.shared.open($0.url) }
    }

    @objc private func revealSelected() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedImages.map(\.url))
    }

    @objc private func copyImage() {
        guard let url = selectedImages.first?.url, let image = NSImage(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @objc private func copyPaths() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedImages.map(\.url.path).joined(separator: "\n"), forType: .string)
    }

    @objc private func trashSelected() {
        let urls = selectedImages.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }
}

private final class HistoryWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class HistoryCollectionView: NSCollectionView {
    var onOpen: (() -> Void)?
    var onCopy: (() -> Void)?
    var onTrash: (() -> Void)?
    var contextMenu: (() -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            onOpen?()
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (Int(event.keyCode), modifiers) {
        case (36, _), (76, _):
            onOpen?()
        case (51, .command):
            onTrash?()
        case (8, .command):
            onCopy?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
        }
        return contextMenu?()
    }
}

private final class HistoryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryItem")
    static let labelHeight: CGFloat = 22

    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var url: URL?

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override func loadView() {
        let container = HistoryItemView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.onAppearanceChange = { [weak self] in self?.updateAppearance() }

        thumbnailView.imageScaling = .scaleProportionallyDown
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        thumbnailView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        thumbnailView.setContentHuggingPriority(.defaultLow, for: .vertical)

        nameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        container.addSubview(thumbnailView)
        container.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            thumbnailView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            thumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            thumbnailView.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -2),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        view = container
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isSelected = false
        url = nil
        thumbnailView.image = nil
    }

    func configure(url: URL, toolTip: String) {
        self.url = url
        nameLabel.stringValue = url.lastPathComponent
        view.toolTip = toolTip
        updateAppearance()
    }

    func setThumbnail(_ image: NSImage?, for url: URL) {
        guard self.url == url else { return }
        thumbnailView.image = image
    }

    private func updateAppearance() {
        guard isViewLoaded else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor : nil
        }
    }
}

private final class HistoryItemView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

private final class ThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init() {
        cache.countLimit = 500
    }

    func thumbnail(for url: URL, maxPixelSize: Int, completion: @escaping (NSImage?) -> Void) {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        queue.addOperation { [cache] in
            let image = Self.makeThumbnail(url: url, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async {
                if let image { cache.setObject(image, forKey: key) }
                completion(image)
            }
        }
    }

    private static func makeThumbnail(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
