//
//  PlayerViewController.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/8/21.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import AVFoundation
import AVKit
import BookPlayerKit
import Combine
import MediaPlayer
import StoreKit
import SwiftUI
import Themeable
import UIKit

class PlayerViewController: UIViewController, MVVMControllerProtocol, Storyboarded {
  var viewModel: PlayerViewModel!
  @IBOutlet private weak var closeButton: UIButton!
  @IBOutlet private weak var closeButtonTop: NSLayoutConstraint!
  @IBOutlet private weak var bottomToolbar: UIToolbar!
  @IBOutlet weak var toolbarBottomConstraint: NSLayoutConstraint!
  @IBOutlet private weak var speedButton: UIBarButtonItem!
  @IBOutlet private weak var sleepButton: UIBarButtonItem!
  @IBOutlet private var sleepLabel: UIBarButtonItem!
  @IBOutlet private var listButton: UIBarButtonItem!
  @IBOutlet private var bookmarkButton: UIBarButtonItem!
  @IBOutlet private weak var moreButton: UIBarButtonItem!

  @IBOutlet private weak var artworkControl: ArtworkControl!
  @IBOutlet private weak var progressSlider: ProgressSlider!
  @IBOutlet private weak var currentTimeLabel: UILabel!
  @IBOutlet private weak var chapterTitleButton: UIButton!
  @IBOutlet private weak var maxTimeButton: UIButton!
  @IBOutlet private weak var progressButton: UIButton!
  @IBOutlet weak var previousChapterButton: UIButton!
  @IBOutlet weak var nextChapterButton: UIButton!
  @IBOutlet weak var rewindIconView: PlayerJumpIconRewind!
  @IBOutlet weak var playIconView: PlayPauseIconView!
  @IBOutlet weak var forwardIconView: PlayerJumpIconForward!
  @IBOutlet weak var containerItemStackView: UIStackView!
  @IBOutlet weak var containerPlayerControlsStackView: UIStackView!
  @IBOutlet weak var containerChapterControlsStackView: UIStackView!
  @IBOutlet weak var containerProgressControlsStackView: UIStackView!
  @IBOutlet weak var lyricsButton: UIButton!
  private var themedStatusBarStyle: UIStatusBarStyle?
  private var panGestureRecognizer: UIPanGestureRecognizer!
  private let dismissThreshold: CGFloat = 44.0 * UIScreen.main.nativeScale
  private var dismissFeedbackTriggered = false

  private var disposeBag = Set<AnyCancellable>()
  private var playingProgressSubscriber: AnyCancellable?
  private var currentChapterSubscriber: AnyCancellable?
  private var updateProgressObserver: NSKeyValueObservation?

  /// Reference to displayed alert, to update the message label with the ongoing timer
  weak var sleepTimerAlert: UIAlertController?
  
  // Transcript viewer support
  private var transcriptViewModel: TranscriptViewerViewModel!
  private var transcriptImporter: TranscriptImporter!
  private var isShowingTranscript = false
  private var buttonStyleTimer: Timer?
  
  // Lyrics viewer support
  private var lyricsViewModel: TranscriptViewerViewModel!
  private var lyricsImporter: TranscriptImporter!
  private var isShowingLyrics = false
  private var lyricsButtonStyleTimer: Timer?

  // computed properties
  override var preferredStatusBarStyle: UIStatusBarStyle {
    let style = ThemeManager.shared.useDarkVariant ? UIStatusBarStyle.lightContent : UIStatusBarStyle.default
    return self.themedStatusBarStyle ?? style
  }

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()

    setup()
    
    setupTranscriptFeatures()
    setupLyricsFeatures()

    setUpTheming()

    setupToolbar()

    setupGestures()

    bindGeneralObservers()

    bindPresenterEvents()

    bindProgressObservers()

    bindPlaybackControlsObservers()

    bindBookPlayingProgressEvents()

    bindTimerObserver()

    self.containerItemStackView.setCustomSpacing(26, after: self.artworkControl)
    toggleArtwork(for: traitCollection)

    self.currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

  }

  override func willTransition(
    to newCollection: UITraitCollection,
    with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.willTransition(to: newCollection, with: coordinator)

    coordinator.animate { [weak self] _ in
      self?.toggleArtwork(for: newCollection)
    }
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)

    /// Patch to fix background layers on default artwork for iPad
    if UIDevice.current.userInterfaceIdiom != .phone,
      artworkControl.artworkImage.isHidden
    {
      artworkControl.setupGradients(with: size)
    }
  }

  /// When the device has a compact vertical size class, there's not enough room to display the artwork
  func toggleArtwork(for trait: UITraitCollection) {
    if trait.verticalSizeClass == .compact {
      artworkControl.alpha = 0
      artworkControl.isHidden = true
    } else {
      artworkControl.alpha = 1
      artworkControl.isHidden = false
    }
  }

  // Prevents dragging the view down from changing the safeAreaInsets.top and .bottom
  // Note: I'm pretty sure there is a better solution for this that I haven't found yet - @pichfl
  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()

    guard
      let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
    else { return }

    let insets: UIEdgeInsets = window.safeAreaInsets

    self.closeButtonTop.constant = self.view.safeAreaInsets.top == 0.0 ? insets.top : 0
    self.toolbarBottomConstraint.constant = self.view.safeAreaInsets.bottom == 0.0 ? insets.bottom : 0
  }

  func setup() {
    self.closeButton.accessibilityLabel = "voiceover_dismiss_player_title".localized

    self.chapterTitleButton.titleLabel?.numberOfLines = 2
    self.chapterTitleButton.titleLabel?.textAlignment = .center
    self.chapterTitleButton.titleLabel?.lineBreakMode = .byWordWrapping
    /// Disabling traits here, as toggling the chapter context with this button does not have the same feedback
    /// like with the `progressButton` action
    self.chapterTitleButton.accessibilityTraits = []

    // Based on Apple books, the player controls are kept the same for right-to-left languages
    self.progressSlider.semanticContentAttribute = .forceLeftToRight
    self.containerPlayerControlsStackView.semanticContentAttribute = .forceLeftToRight
    self.containerChapterControlsStackView.semanticContentAttribute = .forceLeftToRight
    self.containerProgressControlsStackView.semanticContentAttribute = .forceLeftToRight
  }

  func setupPlayerView(with currentItem: PlayableItem) {
    self.artworkControl.setupInfo(
      with: currentItem.title,
      author: currentItem.author
    )

    self.updateView(with: self.viewModel.getCurrentProgressState(currentItem))

    applyTheme(self.themeProvider.currentTheme)

    // Solution thanks to https://forums.developer.apple.com/thread/63166#180445
    self.modalPresentationCapturesStatusBarAppearance = true

    self.setNeedsStatusBarAppearanceUpdate()
    
    // Update transcript button state
    let hasTranscript = LRCService.shared.hasLRCFile(for: currentItem.relativePath)
    self.artworkControl.updateTranscriptButtonVisibility(hasTranscript: hasTranscript)
    
    // Load transcript if available
    if hasTranscript {
      transcriptViewModel.loadTranscript(for: currentItem.relativePath)
    } else {
      transcriptViewModel.clearTranscript()
    }
    
    // Update lyrics button state
    let hasLyrics = LRCService.shared.hasLRCFile(for: currentItem.relativePath)
    self.updateLyricsButtonVisibility(hasLyrics: hasLyrics)
    
    // Load lyrics if available
    if hasLyrics {
      lyricsViewModel.loadTranscript(for: currentItem.relativePath)
    } else {
      lyricsViewModel.clearTranscript()
    }
  }

  func updateView(with progressObject: ProgressObject, shouldSetSliderValue: Bool = true) {
    if shouldSetSliderValue && self.progressSlider.isTracking { return }

    self.currentTimeLabel.text = progressObject.formattedCurrentTime
    self.currentTimeLabel.accessibilityLabel = String(
      describing: String.localizedStringWithFormat(
        self.viewModel.getCurrentTimeVoiceOverPrefix(),
        VoiceOverService.secondsToMinutes(progressObject.currentTime)
      )
    )

    if let progress = progressObject.progress {
      self.progressButton.setTitle(progress, for: .normal)
    }

    if let maxTime = progressObject.maxTime,
      let formattedMaxTime = progressObject.formattedMaxTime
    {

    let title = NSAttributedString(
         string: formattedMaxTime,
         attributes: [
             .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
         ]
    )
    self.maxTimeButton.setAttributedTitle(title, for: .normal)
      
      self.maxTimeButton.accessibilityLabel = String(
        describing: "\(self.viewModel.getMaxTimeVoiceOverPrefix()) \(VoiceOverService.secondsToMinutes(maxTime))"
      )
    }

    self.chapterTitleButton.setTitle(progressObject.chapterTitle, for: .normal)
    self.chapterTitleButton.accessibilityLabel = progressObject.chapterTitle

    if shouldSetSliderValue {
      self.progressSlider.setProgress(progressObject.sliderValue)
    }

    let leftChevron = UIImage(
      systemName: progressObject.prevChapterImageName,
      withConfiguration: UIImage.SymbolConfiguration(
        pointSize: 18,
        weight: .semibold
      )
    )
    let rightChevron = UIImage(
      systemName: progressObject.nextChapterImageName,
      withConfiguration: UIImage.SymbolConfiguration(
        pointSize: 18,
        weight: .semibold
      )
    )

    self.previousChapterButton.setImage(leftChevron, for: .normal)
    self.nextChapterButton.setImage(rightChevron, for: .normal)
    
    // Update transcript time if showing
    if isShowingTranscript {
      transcriptViewModel.updateCurrentTime(progressObject.currentTime)
    }
    
    // Update lyrics time if showing
    if isShowingLyrics {
      lyricsViewModel.updateCurrentTime(progressObject.currentTime)
    }
  }
  
  // MARK: - Transcript Features
  
  func setupTranscriptFeatures() {
    transcriptViewModel = TranscriptViewerViewModel()
    transcriptImporter = TranscriptImporter(presentingViewController: self)
    
    // Add tap handler to transcript button
    artworkControl.transcriptButton.addTarget(
      self,
      action: #selector(handleTranscriptButtonTap),
      for: .touchUpInside
    )
  }
  
  @objc private func handleTranscriptButtonTap() {
    guard let currentItem = viewModel.currentItem else { return }
    
    // If we're already showing the transcript, just toggle back
    if isShowingTranscript {
      toggleTranscriptView()
      return
    }
    
    // Check if transcript exists
    let hasTranscript = transcriptViewModel.hasTranscript(for: currentItem.relativePath)
    
    if !hasTranscript {
      // No transcript yet, show import dialog
      presentTranscriptImportOptions(for: currentItem.relativePath)
    } else {
      // Toggle to show transcript view
      toggleTranscriptView()
    }
  }
  
  private func presentTranscriptImportOptions(for relativePath: String) {
    let alert = UIAlertController(
      title: "Import Transcript",
      message: "Import an .lrc file to enable synchronized text viewing",
      preferredStyle: .actionSheet
    )
    
    alert.addAction(
      UIAlertAction(
        title: "Choose File",
        style: .default,
        handler: { [weak self] _ in
          self?.importTranscriptFile(for: relativePath)
        }
      )
    )
    
    alert.addAction(
      UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    )
    
    if let popoverController = alert.popoverPresentationController {
      popoverController.sourceView = artworkControl.transcriptButton
      popoverController.sourceRect = artworkControl.transcriptButton.bounds
    }
    
    present(alert, animated: true)
  }
  
  private func importTranscriptFile(for relativePath: String) {
    transcriptImporter.importTranscript(for: relativePath) { [weak self] result in
      guard let self = self else { return }
      
      switch result {
      case .success:
        // Load the transcript and show it
        self.transcriptViewModel.loadTranscript(for: relativePath)
        self.artworkControl.updateTranscriptButtonVisibility(hasTranscript: true)
        self.toggleTranscriptView()
        
        // Show success message
        self.showTranscriptImportSuccess()
        
      case .failure(let error):
        // Handle cancelled state silently
        if case TranscriptImporterError.cancelled = error {
          return
        }
        
        // Show error alert for other failures
        self.showTranscriptImportError(error)
      }
    }
  }
  
  private func toggleTranscriptView() {
    guard let currentItem = viewModel.currentItem else { return }
    
    if !isShowingTranscript {
      // Load transcript if not already loaded
      if !transcriptViewModel.hasTranscript {
        transcriptViewModel.loadTranscript(for: currentItem.relativePath)
      }
      
      // Show transcript view
      showTranscriptView()
    } else {
      // Show artwork view
      hideTranscriptView()
    }
  }
  
  private func showTranscriptView() {
    isShowingTranscript = true
    
    // Create and configure SwiftUI hosting controller
    let transcriptView = TranscriptViewer(
      viewModel: transcriptViewModel,
      onLineTap: { [weak self] timestamp in
        self?.viewModel.handleSeekTo(timestamp)
      }
    )
    
    let hostingController = UIHostingController(rootView: transcriptView)
    hostingController.view.backgroundColor = .clear
    
    // Add as child view controller
    addChild(hostingController)
    artworkControl.addSubview(hostingController.view)
    
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.alpha = 0
    
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: artworkControl.topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: artworkControl.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: artworkControl.trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: artworkControl.bottomAnchor)
    ])
    
    hostingController.didMove(toParent: self)
    
    // Create an invisible tap interceptor view over the button area
    let buttonProtector = UIView()
    buttonProtector.backgroundColor = .clear
    buttonProtector.tag = 9999 // Tag to find it later
    artworkControl.addSubview(buttonProtector)
    
    buttonProtector.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      buttonProtector.leadingAnchor.constraint(equalTo: artworkControl.transcriptButton.leadingAnchor, constant: -8),
      buttonProtector.trailingAnchor.constraint(equalTo: artworkControl.transcriptButton.trailingAnchor, constant: 8),
      buttonProtector.topAnchor.constraint(equalTo: artworkControl.transcriptButton.topAnchor, constant: -8),
      buttonProtector.bottomAnchor.constraint(equalTo: artworkControl.transcriptButton.bottomAnchor, constant: 8)
    ])
    
    // Add tap gesture to forward to the button
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTranscriptButtonTap))
    buttonProtector.addGestureRecognizer(tapGesture)
    buttonProtector.isUserInteractionEnabled = true
    
    // Ensure button styling before animation
    ensureTranscriptButtonOnTop()
    
    // Animate transition
    UIView.transition(
      with: artworkControl,
      duration: 0.4,
      options: .transitionFlipFromLeft,
      animations: {
        hostingController.view.alpha = 1
        self.artworkControl.artworkImage.alpha = 0
        self.artworkControl.titleLabel.alpha = 0
        self.artworkControl.authorLabel.alpha = 0
      },
      completion: { _ in
        // After animation, ensure button and protector are on top again
        self.ensureTranscriptButtonOnTop()
        
        // Add another delayed call to ensure styling persists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          self.ensureTranscriptButtonOnTop()
        }
        
        // Start a timer to periodically ensure button stays styled and on top
        self.startButtonStyleTimer()
      }
    )
  }
  
  private func startButtonStyleTimer() {
    // Invalidate any existing timer
    buttonStyleTimer?.invalidate()
    
    // Create a timer that fires every 0.5 seconds to ensure button styling
    buttonStyleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self, self.isShowingTranscript else { return }
      self.ensureTranscriptButtonOnTop()
    }
  }
  
  private func stopButtonStyleTimer() {
    buttonStyleTimer?.invalidate()
    buttonStyleTimer = nil
  }
  
  private func ensureTranscriptButtonOnTop() {
    // Bring transcript button to front to ensure it's always visible and tappable
    artworkControl.bringSubviewToFront(artworkControl.transcriptButton)
    
    // Bring the button protector to front as well
    if let protector = artworkControl.viewWithTag(9999) {
      artworkControl.bringSubviewToFront(protector)
    }
    
    // Re-apply all button styling to ensure it's visible in text view
    let button = artworkControl.transcriptButton!
    
    // Blue circular background
    button.backgroundColor = UIColor.systemBlue
    button.layer.cornerRadius = 20
    
    // Shadow for visibility
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = 0.3
    button.layer.shadowRadius = 4.0
    button.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
    
    // White icon
    button.tintColor = .white
    
    // Z-positioning
    button.layer.zPosition = 1000
    button.isUserInteractionEnabled = true
    button.clipsToBounds = false
    
    // Force the layer to render above everything
    button.layer.masksToBounds = false
  }
  
  private func hideTranscriptView() {
    isShowingTranscript = false
    
    // Stop the button style timer
    stopButtonStyleTimer()
    
    // Find and remove the hosting controller
    for child in children {
      if child is UIHostingController<TranscriptViewer> {
        // Animate transition
        UIView.transition(
          with: artworkControl,
          duration: 0.4,
          options: .transitionFlipFromRight,
          animations: {
            child.view.alpha = 0
            self.artworkControl.artworkImage.alpha = 1
            self.artworkControl.titleLabel.alpha = 1
            self.artworkControl.authorLabel.alpha = 1
          },
          completion: { _ in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
            
            // Remove the button protector view
            if let protector = self.artworkControl.viewWithTag(9999) {
              protector.removeFromSuperview()
            }
          }
        )
        break
      }
    }
  }
  
  private func showTranscriptImportSuccess() {
    let alert = UIAlertController(
      title: "Success",
      message: "Transcript imported successfully",
      preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
  
  private func showTranscriptImportError(_ error: Error) {
    let message: String
    
    if let lrcError = error as? LRCParserError {
      message = lrcError.errorDescription ?? "Failed to parse transcript file"
    } else if let importError = error as? TranscriptImporterError {
      message = importError.errorDescription ?? "Failed to import transcript"
    } else {
      message = error.localizedDescription
    }
    
    let alert = UIAlertController(
      title: "Import Failed",
      message: message,
      preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
  
  // MARK: - Lyrics Features
  
  func setupLyricsFeatures() {
    lyricsViewModel = TranscriptViewerViewModel()
    lyricsImporter = TranscriptImporter(presentingViewController: self)
    
    // Setup lyrics button appearance
    setupLyricsButton()
    
    // Add tap handler to lyrics button
    lyricsButton.addTarget(
      self,
      action: #selector(handleLyricsButtonTap),
      for: .touchUpInside
    )
  }
  
  private func setupLyricsButton() {
    // Make it round with blue background
    lyricsButton.layer.cornerRadius = 20 // 40x40 button / 2 = 20 radius
    lyricsButton.backgroundColor = UIColor.systemBlue
    lyricsButton.clipsToBounds = false
    
    // Add shadow for depth
    lyricsButton.layer.shadowColor = UIColor.black.cgColor
    lyricsButton.layer.shadowOpacity = 0.3
    lyricsButton.layer.shadowRadius = 4.0
    lyricsButton.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
    
    // Set up image with proper size
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    let image = UIImage(systemName: "music.note.list", withConfiguration: config)
    lyricsButton.setImage(image, for: .normal)
    lyricsButton.tintColor = .white
    
    // Ensure button is always interactive and on top
    lyricsButton.isUserInteractionEnabled = true
    lyricsButton.layer.zPosition = 1000
    
    lyricsButton.isAccessibilityElement = true
    lyricsButton.accessibilityLabel = "Toggle Lyrics"
  }
  
  private func updateLyricsButtonVisibility(hasLyrics: Bool) {
    // Always show the button, but we could change the icon based on state
    lyricsButton.isHidden = false
    
    // Update icon based on whether lyrics exists
    let iconName = hasLyrics ? "music.note.list" : "music.note.list"
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    let image = UIImage(systemName: iconName, withConfiguration: config)
    lyricsButton.setImage(image, for: .normal)
    
    // Ensure blue background and properties are maintained
    lyricsButton.backgroundColor = UIColor.systemBlue
    lyricsButton.tintColor = .white
    lyricsButton.layer.zPosition = 1000
  }
  
  @objc private func handleLyricsButtonTap() {
    guard let currentItem = viewModel.currentItem else { return }
    
    // If we're already showing the lyrics, just toggle back
    if isShowingLyrics {
      toggleLyricsView()
      return
    }
    
    // Check if lyrics exists
    let hasLyrics = lyricsViewModel.hasTranscript(for: currentItem.relativePath)
    
    if !hasLyrics {
      // No lyrics yet, show import dialog
      presentLyricsImportOptions(for: currentItem.relativePath)
    } else {
      // Toggle to show lyrics view
      toggleLyricsView()
    }
  }
  
  private func presentLyricsImportOptions(for relativePath: String) {
    let alert = UIAlertController(
      title: "Import Lyrics",
      message: "Import an .lrc file to enable synchronized lyrics viewing",
      preferredStyle: .actionSheet
    )
    
    alert.addAction(
      UIAlertAction(
        title: "Choose File",
        style: .default,
        handler: { [weak self] _ in
          self?.importLyricsFile(for: relativePath)
        }
      )
    )
    
    alert.addAction(
      UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    )
    
    if let popoverController = alert.popoverPresentationController {
      popoverController.sourceView = lyricsButton
      popoverController.sourceRect = lyricsButton.bounds
    }
    
    present(alert, animated: true)
  }
  
  private func importLyricsFile(for relativePath: String) {
    lyricsImporter.importTranscript(for: relativePath) { [weak self] result in
      guard let self = self else { return }
      
      switch result {
      case .success:
        // Load the lyrics and show it
        self.lyricsViewModel.loadTranscript(for: relativePath)
        self.updateLyricsButtonVisibility(hasLyrics: true)
        self.toggleLyricsView()
        
        // Show success message
        self.showLyricsImportSuccess()
        
      case .failure(let error):
        // Handle cancelled state silently
        if case TranscriptImporterError.cancelled = error {
          return
        }
        
        // Show error alert for other failures
        self.showLyricsImportError(error)
      }
    }
  }
  
  private func toggleLyricsView() {
    guard let currentItem = viewModel.currentItem else { return }
    
    if !isShowingLyrics {
      // Load lyrics if not already loaded
      if !lyricsViewModel.hasTranscript {
        lyricsViewModel.loadTranscript(for: currentItem.relativePath)
      }
      
      // Show lyrics view
      showLyricsView()
    } else {
      // Show artwork view
      hideLyricsView()
    }
  }
  
  private func showLyricsView() {
    isShowingLyrics = true
    
    // Create and configure SwiftUI hosting controller
    let lyricsView = TranscriptViewer(
      viewModel: lyricsViewModel,
      onLineTap: { [weak self] timestamp in
        self?.viewModel.handleSeekTo(timestamp)
      }
    )
    
    let hostingController = UIHostingController(rootView: lyricsView)
    hostingController.view.backgroundColor = .clear
    
    // Add as child view controller
    addChild(hostingController)
    artworkControl.addSubview(hostingController.view)
    
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.alpha = 0
    
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: artworkControl.topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: artworkControl.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: artworkControl.trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: artworkControl.bottomAnchor)
    ])
    
    hostingController.didMove(toParent: self)
    
    // Create an invisible tap interceptor view over the button area
    let buttonProtector = UIView()
    buttonProtector.backgroundColor = .clear
    buttonProtector.tag = 9998 // Different tag from transcript (9999)
    artworkControl.addSubview(buttonProtector)
    
    buttonProtector.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      buttonProtector.leadingAnchor.constraint(equalTo: lyricsButton.leadingAnchor, constant: -8),
      buttonProtector.trailingAnchor.constraint(equalTo: lyricsButton.trailingAnchor, constant: 8),
      buttonProtector.topAnchor.constraint(equalTo: lyricsButton.topAnchor, constant: -8),
      buttonProtector.bottomAnchor.constraint(equalTo: lyricsButton.bottomAnchor, constant: 8)
    ])
    
    // Add tap gesture to forward to the button
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleLyricsButtonTap))
    buttonProtector.addGestureRecognizer(tapGesture)
    buttonProtector.isUserInteractionEnabled = true
    
    // Ensure button styling before animation
    ensureLyricsButtonOnTop()
    
    // Animate transition
    UIView.transition(
      with: artworkControl,
      duration: 0.4,
      options: .transitionFlipFromLeft,
      animations: {
        hostingController.view.alpha = 1
        self.artworkControl.artworkImage.alpha = 0
        self.artworkControl.titleLabel.alpha = 0
        self.artworkControl.authorLabel.alpha = 0
      },
      completion: { _ in
        // After animation, ensure button and protector are on top again
        self.ensureLyricsButtonOnTop()
        
        // Add another delayed call to ensure styling persists
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          self.ensureLyricsButtonOnTop()
        }
        
        // Start a timer to periodically ensure button stays styled and on top
        self.startLyricsButtonStyleTimer()
      }
    )
  }
  
  private func startLyricsButtonStyleTimer() {
    // Invalidate any existing timer
    lyricsButtonStyleTimer?.invalidate()
    
    // Create a timer that fires every 0.5 seconds to ensure button styling
    lyricsButtonStyleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self, self.isShowingLyrics else { return }
      self.ensureLyricsButtonOnTop()
    }
  }
  
  private func stopLyricsButtonStyleTimer() {
    lyricsButtonStyleTimer?.invalidate()
    lyricsButtonStyleTimer = nil
  }
  
  private func ensureLyricsButtonOnTop() {
    // Bring lyrics button to front to ensure it's always visible and tappable
    artworkControl.bringSubviewToFront(lyricsButton)
    
    // Bring the button protector to front as well
    if let protector = artworkControl.viewWithTag(9998) {
      artworkControl.bringSubviewToFront(protector)
    }
    
    // Re-apply all button styling to ensure it's visible in text view
    let button = lyricsButton!
    
    // Blue circular background
    button.backgroundColor = UIColor.systemBlue
    button.layer.cornerRadius = 20
    
    // Shadow for visibility
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = 0.3
    button.layer.shadowRadius = 4.0
    button.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
    
    // White icon
    button.tintColor = .white
    
    // Z-positioning
    button.layer.zPosition = 1000
    button.isUserInteractionEnabled = true
    button.clipsToBounds = false
    
    // Force the layer to render above everything
    button.layer.masksToBounds = false
  }
  
  private func hideLyricsView() {
    isShowingLyrics = false
    
    // Stop the button style timer
    stopLyricsButtonStyleTimer()
    
    // Find and remove the hosting controller
    for child in children {
      if child is UIHostingController<TranscriptViewer> {
        // Animate transition
        UIView.transition(
          with: artworkControl,
          duration: 0.4,
          options: .transitionFlipFromRight,
          animations: {
            child.view.alpha = 0
            self.artworkControl.artworkImage.alpha = 1
            self.artworkControl.titleLabel.alpha = 1
            self.artworkControl.authorLabel.alpha = 1
          },
          completion: { _ in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
            
            // Remove the button protector view
            if let protector = self.artworkControl.viewWithTag(9998) {
              protector.removeFromSuperview()
            }
          }
        )
        break
      }
    }
  }
  
  private func showLyricsImportSuccess() {
    let alert = UIAlertController(
      title: "Success",
      message: "Lyrics imported successfully",
      preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
  
  private func showLyricsImportError(_ error: Error) {
    let message: String
    
    if let lrcError = error as? LRCParserError {
      message = lrcError.errorDescription ?? "Failed to parse lyrics file"
    } else if let importError = error as? TranscriptImporterError {
      message = importError.errorDescription ?? "Failed to import lyrics"
    } else {
      message = error.localizedDescription
    }
    
    let alert = UIAlertController(
      title: "Import Failed",
      message: message,
      preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
}

// MARK: - Observers
extension PlayerViewController {
  override func accessibilityPerformEscape() -> Bool {
    viewModel.dismiss()
    return true
  }
  
  func bindProgressObservers() {
    self.progressSlider.publisher(for: .touchDown)
      .sink { [weak self] _ in
        // Disable recurring playback time events
        self?.playingProgressSubscriber?.cancel()

        self?.viewModel.handleSliderDownEvent()
      }.store(in: &disposeBag)

    self.progressSlider.publisher(for: .touchUpInside)
      .merge(with: self.progressSlider.publisher(for: .touchUpOutside))
      .sink { [weak self] sender in
        guard let slider = sender as? UISlider else { return }

        self?.viewModel.handleSliderUpEvent(with: slider.value)
        // Enable back recurring playback time events after one second
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
          self?.bindBookPlayingProgressEvents()
        }
      }.store(in: &disposeBag)

    self.progressSlider.publisher(for: .valueChanged)
      .sink { [weak self] sender in
        guard let self = self,
          let slider = sender as? UISlider
        else { return }
        self.progressSlider.setNeedsDisplay()

        let progressObject = self.viewModel.processSliderValueChangedEvent(with: slider.value)

        self.updateView(with: progressObject, shouldSetSliderValue: false)
      }.store(in: &disposeBag)
  }

  func bindBookPlayingProgressEvents() {
    self.playingProgressSubscriber?.cancel()
    self.playingProgressSubscriber = NotificationCenter.default.publisher(for: .bookPlaying)
      .sink { [weak self] _ in
        guard let self = self else { return }
        self.updateView(with: self.viewModel.getCurrentProgressState())
      }
  }

  func bindPlaybackControlsObservers() {
    bindPlaybackStateObservers()
    bindTimeAndProgressObservers()
    bindMediaControlObservers()
    bindChapterControlObservers()
  }

  private func bindPlaybackStateObservers() {
    viewModel.isPlayingObserver()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isPlaying in
        self?.playIconView.isPlaying = isPlaying
      }
      .store(in: &disposeBag)

    playIconView.observeActionEvents()
      .sink { [weak self] _ in
        self?.viewModel.handlePlayPauseAction()
      }
      .store(in: &disposeBag)
  }

  private func bindTimeAndProgressObservers() {
    maxTimeButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        guard let self = self,
              !self.progressSlider.isTracking
        else { return }

        let progressObject = self.viewModel.processToggleMaxTime()
        self.updateView(with: progressObject)
      }
      .store(in: &disposeBag)

    updateProgressObserver = UserDefaults.standard.observe(
      \.userSettingsUpdateProgress,
       options: [.new]
    ) { [weak self] object, change in
      guard let self,
            let newValue = change.newValue,
            newValue == true
      else { return }

      self.viewModel.reloadSharedFlags()
      let progressObject = self.viewModel.getCurrentProgressState()
      self.updateView(with: progressObject)

      object.set(false, forKey: Constants.UserDefaults.updateProgress)
    }

    progressButton.publisher(for: .touchUpInside)
      .merge(with: chapterTitleButton.publisher(for: .touchUpInside))
      .sink { [weak self] _ in
        guard let self = self,
              !self.progressSlider.isTracking
        else { return }

        let progressObject = self.viewModel.processToggleProgressState()
        self.updateView(with: progressObject)
      }
      .store(in: &disposeBag)
  }

  private func bindMediaControlObservers() {
    rewindIconView.observeActionEvents()
      .sink { [weak self] _ in
        self?.viewModel.handleRewindAction()
      }
      .store(in: &disposeBag)

    forwardIconView.observeActionEvents()
      .sink { [weak self] _ in
        self?.viewModel.handleForwardAction()
      }
      .store(in: &disposeBag)
  }

  private func bindChapterControlObservers() {
    previousChapterButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        self?.viewModel.handlePreviousChapterAction()
      }
      .store(in: &disposeBag)

    nextChapterButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        self?.viewModel.handleNextChapterAction()
      }
      .store(in: &disposeBag)
  }

  func bindTimerObserver() {
    viewModel.toolbarSleepDescriptionPublisher().sink { [weak self] toolbarDescription in
      guard let self else { return }

      self.sleepLabel.title = toolbarDescription

      if let timeFormatted = toolbarDescription {
        self.sleepLabel.isAccessibilityElement = true
        let remainingTitle = String(
          describing: String.localizedStringWithFormat("sleep_remaining_title".localized, timeFormatted)
        )
        self.sleepLabel.accessibilityLabel = String(describing: remainingTitle)

        if let items = self.bottomToolbar.items,
          !items.contains(self.sleepLabel)
        {
          self.updateToolbar(true, animated: true)
        }
      } else {
        self.sleepLabel.isAccessibilityElement = false

        if let items = self.bottomToolbar.items,
          items.contains(self.sleepLabel)
        {
          self.updateToolbar(false, animated: true)
        }
      }
    }.store(in: &disposeBag)

    viewModel.sleepAlertMessagePublisher().sink { [weak self] alertMessage in
      self?.sleepTimerAlert?.message = alertMessage
    }.store(in: &disposeBag)
  }

  func bindGeneralObservers() {
    NotificationCenter.default.publisher(for: .requestReview)
      .debounce(for: 1.0, scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.viewModel.requestReview()
      }
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .bookEnd)
      .debounce(for: 1.0, scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.viewModel.requestReview()
      }
      .store(in: &disposeBag)

    self.closeButton.publisher(for: .touchUpInside)
      .sink { [weak self] _ in
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self?.viewModel.dismiss()
      }
      .store(in: &disposeBag)

    self.viewModel.currentItemObserver()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] item in
        self?.currentChapterSubscriber?.cancel()
        guard let self = self,
          let item = item
        else { return }

        self.setupPlayerView(with: item)
        self.bindCurrentChapterObserver(for: item)
      }.store(in: &disposeBag)

    self.viewModel.currentSpeedObserver()
      .removeDuplicates()
      .sink { [weak self] speed in
        guard let self = self else { return }

        self.speedButton.title = self.formatSpeed(speed)
        self.speedButton.accessibilityLabel = String(
          describing: self.formatSpeed(speed) + " \("speed_title".localized)"
        )

        // Only update progress if the player is in pause state
        guard !self.playIconView.isPlaying else { return }

        let progressObject = self.viewModel.getCurrentProgressState()

        self.updateView(with: progressObject)
      }.store(in: &disposeBag)
  }

  func bindCurrentChapterObserver(for item: PlayableItem) {
    currentChapterSubscriber = item.$currentChapter
      .receive(on: DispatchQueue.main)
      .sink { [weak self, item] chapter in
      let relativePath: String

      if let chapter,
        ArtworkService.isCached(relativePath: chapter.relativePath)
      {
        relativePath = chapter.relativePath
      } else {
        relativePath = item.relativePath
      }

      self?.artworkControl.setupArtworkImage(relativePath: relativePath)
    }
  }

  func bindPresenterEvents() {
    self.viewModel.eventsPublisher
      .sink { [weak self] event in
        switch event {
        case .sleepTimerAlert(let content):
          self?.presentSleepTimerAlert(content)
        case .customSleepTimer(let title):
          self?.presentCustomSleepTimerAlert(title)
        case .updateProgress(let progress):
          self?.updateView(with: progress)
        }
      }.store(in: &disposeBag)
  }
}

// MARK: - Toolbar
extension PlayerViewController {
  func setupToolbar() {
    self.bottomToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
    self.bottomToolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
    self.speedButton.setTitleTextAttributes(
      [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0, weight: .semibold)],
      for: .normal
    )
    self.previousChapterButton.accessibilityLabel = "chapters_previous_title".localized
    self.nextChapterButton.accessibilityLabel = "chapters_next_title".localized
    self.bookmarkButton.accessibilityLabel = "bookmark_create_title".localized
    self.sleepButton.accessibilityLabel = "settings_siri_sleeptimer_title".localized
    self.listButton.accessibilityLabel =
      UserDefaults.standard.bool(forKey: Constants.UserDefaults.playerListPrefersBookmarks)
      ? "bookmarks_title".localized : "chapters_title".localized
    self.moreButton.accessibilityLabel = "more_title".localized
  }

  func updateToolbar(_ showTimerLabel: Bool = false, animated: Bool = false) {
    let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

    var items: [UIBarButtonItem] = [
      self.speedButton,
      spacer,
      self.sleepButton,
    ]

    if showTimerLabel {
      items.append(self.sleepLabel)
    }

    items.append(spacer)
    items.append(self.bookmarkButton)

    items.append(spacer)
    items.append(self.listButton)

    items.append(spacer)
    items.append(self.moreButton)

    self.bottomToolbar.setItems(items, animated: animated)
  }
}

// MARK: - Toolbar Actions

extension PlayerViewController {
  @IBAction func showList(_ sender: UIBarButtonItem) {
    self.viewModel.showList()
  }

  @IBAction func createBookmark(_ sender: UIBarButtonItem) {
    self.viewModel.createBookmark(vc: self)
  }

  @IBAction func setSpeed() {
    self.viewModel.showControls()
  }

  @IBAction func setSleepTimer() {
    self.viewModel.showSleepTimerActions()
  }

  func presentSleepTimerAlert(_ content: BPAlertContent) {
    let alert = buildAlert(content)
    sleepTimerAlert = alert

    alert.popoverPresentationController?.permittedArrowDirections = .any
    alert.popoverPresentationController?.barButtonItem = sleepButton

    present(alert, animated: true, completion: nil)
  }

  func presentCustomSleepTimerAlert(_ title: String) {
    let customTimerAlert = UIAlertController(
      title: title,
      message: "\n\n\n\n\n\n\n\n\n\n",
      preferredStyle: .actionSheet
    )

    let datePicker = UIDatePicker()
    datePicker.datePickerMode = .countDownTimer
    if let customTimerDuration = viewModel.getLastCustomSleepTimerDuration() {
      datePicker.countDownDuration = customTimerDuration
    }
    customTimerAlert.view.addSubview(datePicker)
    customTimerAlert.addAction(
      UIAlertAction(
        title: "ok_button".localized,
        style: .default,
        handler: { [weak self] _ in
          self?.viewModel.handleCustomSleepTimerOption(seconds: datePicker.countDownDuration)
        }
      )
    )
    customTimerAlert.addAction(
      UIAlertAction(title: "cancel_button".localized, style: .cancel, handler: nil)
    )

    datePicker.translatesAutoresizingMaskIntoConstraints = false
    datePicker.widthAnchor.constraint(
      equalTo: datePicker.superview!.widthAnchor
    ).isActive = true
    datePicker.topAnchor.constraint(
      equalTo: datePicker.superview!.topAnchor,
      constant: 30
    ).isActive = true

    customTimerAlert.popoverPresentationController?.barButtonItem = sleepButton

    present(customTimerAlert, animated: true, completion: nil)
  }

  @IBAction func showMore() {
    guard self.viewModel.hasLoadedBook() else { return }

    let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    actionSheet.addAction(
      UIAlertAction(
        title: self.viewModel.getListTitleForMoreAction(),
        style: .default,
        handler: { [weak self] _ in self?.viewModel.showListFromMoreAction() }
      )
    )

    actionSheet.addAction(
      UIAlertAction(
        title: "jump_start_title".localized,
        style: .default,
        handler: { [weak self] _ in self?.viewModel.handleJumpToStart() }
      )
    )

    let markTitle =
      self.viewModel.isBookFinished() ? "mark_unfinished_title".localized : "mark_finished_title".localized

    actionSheet.addAction(
      UIAlertAction(
        title: markTitle,
        style: .default,
        handler: { [weak self] _ in self?.viewModel.handleMarkCompletion() }
      )
    )

    actionSheet.addAction(
      UIAlertAction(
        title: "button_free_title".localized,
        style: .default,
        handler: { [weak self] _ in self?.viewModel.showButtonFree() }
      )
    )

    actionSheet.addAction(
      UIAlertAction(
        title: self.viewModel.isRepeatEnabled()
          ? "repeat_turn_off_title".localized : "repeat_turn_on_title".localized,
        style: .default,
        handler: { [weak self] _ in self?.viewModel.handleEnableRepeat() }
      )
    )

    actionSheet.addAction(UIAlertAction(title: "cancel_button".localized, style: .cancel, handler: nil))

    if let popoverPresentationController = actionSheet.popoverPresentationController {
      popoverPresentationController.barButtonItem = moreButton
    }

    self.present(actionSheet, animated: true, completion: nil)
  }
}

extension PlayerViewController: UIGestureRecognizerDelegate {
  func setupGestures() {
    self.panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.panAction))
    self.panGestureRecognizer.delegate = self
    self.panGestureRecognizer.maximumNumberOfTouches = 1
    self.panGestureRecognizer.cancelsTouchesInView = true

    self.view.addGestureRecognizer(self.panGestureRecognizer)
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer == self.panGestureRecognizer {
      return limitPanAngle(self.panGestureRecognizer, degreesOfFreedom: 45.0, comparator: .greaterThan)
    }

    return true
  }

  private func updatePresentedViewForTranslation(_ yTranslation: CGFloat) {
    let translation: CGFloat = rubberBandDistance(yTranslation, dimension: self.view.frame.height, constant: 0.55)

    self.view?.transform = CGAffineTransform(translationX: 0, y: max(translation, 0.0))
  }

  @objc private func panAction(gestureRecognizer: UIPanGestureRecognizer) {
    guard gestureRecognizer.isEqual(self.panGestureRecognizer) else {
      return
    }

    switch gestureRecognizer.state {
    case .began:
      gestureRecognizer.setTranslation(CGPoint(x: 0, y: 0), in: self.view.superview)

    case .changed:
      let translation = gestureRecognizer.translation(in: self.view)

      self.updatePresentedViewForTranslation(translation.y)

      if translation.y > self.dismissThreshold, !self.dismissFeedbackTriggered {
        self.dismissFeedbackTriggered = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }

    case .ended, .cancelled, .failed:
      let translation = gestureRecognizer.translation(in: self.view)

      if translation.y > self.dismissThreshold {
        self.viewModel.dismiss()
        return
      }

      self.dismissFeedbackTriggered = false

      UIView.animate(
        withDuration: 0.3,
        delay: 0.0,
        usingSpringWithDamping: 0.75,
        initialSpringVelocity: 1.5,
        options: .preferredFramesPerSecond60,
        animations: {
          self.view?.transform = .identity
        }
      )

    default: break
    }
  }
}

extension PlayerViewController: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    self.themedStatusBarStyle =
      theme.useDarkVariant
      ? .lightContent
      : .default
    setNeedsStatusBarAppearanceUpdate()

    self.view.backgroundColor = theme.systemBackgroundColor
    self.bottomToolbar.tintColor = theme.secondaryColor
    self.closeButton.tintColor = theme.linkColor

    self.progressSlider.tintColor = theme.linkColor
    self.progressSlider.minimumTrackTintColor = theme.linkColor
    self.progressSlider.maximumTrackTintColor = theme.linkColor.withAlpha(newAlpha: 0.3)

    self.currentTimeLabel.textColor = theme.secondaryColor
    self.maxTimeButton.setTitleColor(theme.secondaryColor, for: .normal)
    self.progressButton.setTitleColor(theme.secondaryColor, for: .normal)
    self.chapterTitleButton.setTitleColor(theme.primaryColor, for: .normal)
    self.previousChapterButton.tintColor = theme.primaryColor
    self.nextChapterButton.tintColor = theme.primaryColor
  }
}
