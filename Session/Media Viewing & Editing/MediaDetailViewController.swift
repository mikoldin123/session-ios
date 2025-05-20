// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import AVKit
import AVFoundation
import SessionUIKit
import SignalUtilitiesKit
import SessionMessagingKit
import SessionUtilitiesKit

public enum MediaGalleryOption {
    case sliderEnabled
    case showAllMediaButton
}

class MediaDetailViewController: OWSViewController, UIScrollViewDelegate {
    private let dependencies: Dependencies
    public let galleryItem: MediaGalleryViewModel.Item
    public weak var delegate: MediaDetailViewControllerDelegate?
    
    // MARK: - UI
    
    private var mediaViewBottomConstraint: NSLayoutConstraint?
    private var mediaViewLeadingConstraint: NSLayoutConstraint?
    private var mediaViewTopConstraint: NSLayoutConstraint?
    private var mediaViewTrailingConstraint: NSLayoutConstraint?
    
    private lazy var scrollView: UIScrollView = {
        let result: UIScrollView = UIScrollView()
        result.showsVerticalScrollIndicator = false
        result.showsHorizontalScrollIndicator = false
        result.contentInsetAdjustmentBehavior = .never
        result.decelerationRate = .fast
        result.zoomScale = 1
        result.delegate = self
        
        return result
    }()
    
    public lazy var mediaView: SessionImageView = {
        let result: SessionImageView = SessionImageView(
            dataManager: dependencies[singleton: .imageDataManager]
        )
        result.translatesAutoresizingMaskIntoConstraints = false
        result.clipsToBounds = true
        result.contentMode = .scaleAspectFit
        result.isUserInteractionEnabled = true
        result.layer.allowsEdgeAntialiasing = true
        result.themeBackgroundColor = .newConversation_background
        
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        result.layer.minificationFilter = .trilinear
        result.layer.magnificationFilter = .trilinear
        
        // We add these gestures to mediaView rather than
        // the root view so that interacting with the video player
        // progres bar doesn't trigger any of these gestures.
        let doubleTap: UITapGestureRecognizer = UITapGestureRecognizer(
            target: MediaDetailViewController.self,
            action: #selector(didDoubleTapImage(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        result.addGestureRecognizer(doubleTap)

        let singleTap: UITapGestureRecognizer = UITapGestureRecognizer(
            target: MediaDetailViewController.self,
            action: #selector(didSingleTapImage(_:))
        )
        singleTap.require(toFail: doubleTap)
        result.addGestureRecognizer(singleTap)
        
        return result
    }()
    
    private lazy var playVideoButton: UIButton = {
        let result: UIButton = UIButton()
        result.contentMode = .scaleAspectFill
        result.setBackgroundImage(UIImage(named: "CirclePlay"), for: .normal)
        result.addTarget(self, action: #selector(playVideo), for: .touchUpInside)
        result.alpha = 0
        
        let playButtonSize: CGFloat = Values.scaleFromIPhone5(70)
        result.set(.width, to: playButtonSize)
        result.set(.height, to: playButtonSize)
        
        return result
    }()
    
    // MARK: - Initialization
    
    init(
        galleryItem: MediaGalleryViewModel.Item,
        delegate: MediaDetailViewControllerDelegate? = nil,
        using dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        self.galleryItem = galleryItem
        self.delegate = delegate
        
        super.init(nibName: nil, bundle: nil)
        
        // We cache the image data in case the attachment stream is deleted.
        galleryItem.attachment.thumbnail(
            size: .large,
            using: dependencies,
            success: { [weak self] thumbnailPath, _, _ in
                self?.mediaView.loadImage(from: thumbnailPath) {
                    guard self?.isViewLoaded == true else { return }
                    
                    self?.scrollView.zoomScale = 1
                    self?.updateMinZoomScale()
                }
            },
            failure: {
                Log.error(.media, "Could not load media.")
            }
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.themeBackgroundColor = .newConversation_background
        
        self.view.addSubview(scrollView)
        self.view.addSubview(playVideoButton)
        scrollView.addSubview(mediaView)
        
        scrollView.pin(to: self.view)
        playVideoButton.center(in: self.view)
        mediaViewLeadingConstraint = mediaView.pin(.leading, to: .leading, of: scrollView)
        mediaViewTopConstraint = mediaView.pin(.top, to: .top, of: scrollView)
        mediaViewTrailingConstraint = mediaView.pin(.trailing, to: .trailing, of: scrollView)
        mediaViewBottomConstraint = mediaView.pin(.bottom, to: .bottom, of: scrollView)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.resetMediaFrame()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.parent == nil || !(self.parent is MediaPageViewController) {
            parentDidAppear()
        }
    }
    
    public func parentDidAppear() {
        mediaView.startAnimationLoop()
        
        if self.galleryItem.attachment.isVideo {
            UIView.animate(withDuration: 0.2) { self.playVideoButton.alpha = 1 }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.updateMinZoomScale()
        self.centerMediaViewConstraints()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        UIView.animate(withDuration: 0.15) { [weak playVideoButton] in playVideoButton?.alpha = 0 }
    }
    
    // MARK: - Functions
    
    private func updateMinZoomScale() {
        let maybeImageSize: CGSize? = mediaView.image?.size
        
        guard let imageSize: CGSize = maybeImageSize else {
            self.scrollView.minimumZoomScale = 1
            self.scrollView.maximumZoomScale = 1
            self.scrollView.zoomScale = 1
            return
        }
        
        let viewSize: CGSize = self.scrollView.bounds.size
        
        guard imageSize.width > 0 && imageSize.height > 0 else {
            Log.error(.media, "Invalid image dimensions (\(imageSize.width), \(imageSize.height))")
            return
        }
        
        let scaleWidth: CGFloat = (viewSize.width / imageSize.width)
        let scaleHeight: CGFloat = (viewSize.height / imageSize.height)
        let minScale: CGFloat = min(scaleWidth, scaleHeight)

        if minScale != self.scrollView.minimumZoomScale {
            self.scrollView.minimumZoomScale = minScale
            self.scrollView.maximumZoomScale = (minScale * 8)
            self.scrollView.zoomScale = minScale
        }
    }
    
    public func zoomOut(animated: Bool) {
        if self.scrollView.zoomScale != self.scrollView.minimumZoomScale {
            self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: animated)
        }
    }

    // MARK: - Gesture Recognizers

    @objc private func didSingleTapImage(_ gesture: UITapGestureRecognizer) {
        self.delegate?.mediaDetailViewControllerDidTapMedia(self)
    }

    @objc private func didDoubleTapImage(_ gesture: UITapGestureRecognizer) {
        guard self.scrollView.zoomScale == self.scrollView.minimumZoomScale else {
            // If already zoomed in at all, zoom out all the way.
            self.zoomOut(animated: true)
            return
        }
        
        let doubleTapZoomScale: CGFloat = 2
        let zoomWidth: CGFloat = (self.scrollView.bounds.width / doubleTapZoomScale)
        let zoomHeight: CGFloat = (self.scrollView.bounds.height / doubleTapZoomScale)

        // Center zoom rect around tapLocation
        let tapLocation: CGPoint = gesture.location(in: self.scrollView)
        let zoomX: CGFloat = max(0, tapLocation.x - zoomWidth / 2)
        let zoomY: CGFloat = max(0, tapLocation.y - zoomHeight / 2)
        let zoomRect: CGRect = CGRect(x: zoomX, y: zoomY, width: zoomWidth, height: zoomHeight)
        let translatedRect: CGRect = self.mediaView.convert(zoomRect, to: self.scrollView)
        
        self.scrollView.zoom(to: translatedRect, animated: true)
    }

    public func didPressPlayBarButton() {
        self.playVideo()
    }

    // MARK: - UIScrollViewDelegate
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.mediaView
    }
    
    private func centerMediaViewConstraints() {
        let scrollViewSize: CGSize = self.scrollView.bounds.size
        let imageViewSize: CGSize = self.mediaView.frame.size
        
        // We want to modify the yOffset so the content remains centered on the screen (we can do this
        // by subtracting half the parentViewController's y position)
        //
        // Note: Due to weird partial-pixel value rendering behaviours we need to round the inset either
        // up or down depending on which direction the partial-pixel would end up rounded to make it
        // align correctly
        let halfHeightDiff: CGFloat = ((self.scrollView.bounds.size.height - self.mediaView.frame.size.height) / 2)
        let shouldRoundUp: Bool = (round(halfHeightDiff) - halfHeightDiff > 0)

        let yOffset: CGFloat = (
            round((scrollViewSize.height - imageViewSize.height) / 2) -
            (shouldRoundUp ?
                ceil((self.parent?.view.frame.origin.y ?? 0) / 2) :
                floor((self.parent?.view.frame.origin.y ?? 0) / 2)
            )
        )

        self.mediaViewTopConstraint?.constant = yOffset
        self.mediaViewBottomConstraint?.constant = yOffset

        let xOffset: CGFloat = max(0, (scrollViewSize.width - imageViewSize.width) / 2)
        self.mediaViewLeadingConstraint?.constant = xOffset
        self.mediaViewTrailingConstraint?.constant = xOffset
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        self.centerMediaViewConstraints()
        self.view.layoutIfNeeded()
    }

    private func resetMediaFrame() {
        // HACK: Setting the frame to itself *seems* like it should be a no-op, but
        // it ensures the content is drawn at the right frame. In particular I was
        // reproducibly seeing some images squished (they were EXIF rotated, maybe
        // related). similar to this report:
        // https://stackoverflow.com/questions/27961884/swift-uiimageview-stretched-aspect
        self.view.layoutIfNeeded()
        self.mediaView.frame = self.mediaView.frame
    }

    // MARK: - Video Playback

    @objc public func playVideo() {
        guard
            let originalFilePath: String = self.galleryItem.attachment.originalFilePath(using: dependencies),
            dependencies[singleton: .fileManager].fileExists(atPath: originalFilePath)
        else { return Log.error(.media, "Missing video file") }
        
        let videoUrl: URL = URL(fileURLWithPath: originalFilePath)
        let player: AVPlayer = AVPlayer(url: videoUrl)
        let viewController: AVPlayerViewController = AVPlayerViewController()
        viewController.player = player
        self.present(viewController, animated: true) { [weak player] in
            player?.play()
        }
    }
}

// MARK: - MediaDetailViewControllerDelegate

protocol MediaDetailViewControllerDelegate: AnyObject {
    func mediaDetailViewControllerDidTapMedia(_ mediaDetailViewController: MediaDetailViewController)
}
