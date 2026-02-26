//
//  ArtworkTranscriptContainer.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import UIKit
import SwiftUI
import BookPlayerKit

/// Container view that can display either artwork or transcript
class ArtworkTranscriptContainer: UIView {
  
  private let artworkControl: ArtworkControl
  private var transcriptHostingController: UIViewController?
  private weak var parentViewController: UIViewController?
  
  private var isShowingTranscript = false
  
  var onSeekToTimestamp: ((TimeInterval) -> Void)?
  
  init(artworkControl: ArtworkControl, parentViewController: UIViewController) {
    self.artworkControl = artworkControl
    self.parentViewController = parentViewController
    super.init(frame: .zero)
    
    setupArtworkControl()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private func setupArtworkControl() {
    addSubview(artworkControl)
    artworkControl.translatesAutoresizingMaskIntoConstraints = false
    
    NSLayoutConstraint.activate([
      artworkControl.topAnchor.constraint(equalTo: topAnchor),
      artworkControl.leadingAnchor.constraint(equalTo: leadingAnchor),
      artworkControl.trailingAnchor.constraint(equalTo: trailingAnchor),
      artworkControl.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }
  
  func toggleView(viewModel: TranscriptViewerViewModel) {
    if isShowingTranscript {
      showArtwork()
    } else {
      showTranscript(viewModel: viewModel)
    }
  }
  
  private func showTranscript(viewModel: TranscriptViewerViewModel) {
    guard let parent = parentViewController else { return }
    
    isShowingTranscript = true
    
    // Create SwiftUI view
    let transcriptView = TranscriptViewer(
      viewModel: viewModel,
      onLineTap: { [weak self] timestamp in
        self?.onSeekToTimestamp?(timestamp)
      }
    )
    
    let hostingController = UIHostingController(rootView: transcriptView)
    hostingController.view.backgroundColor = .clear
    
    // Add as child view controller
    parent.addChild(hostingController)
    addSubview(hostingController.view)
    
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.alpha = 0
    
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    
    hostingController.didMove(toParent: parent)
    transcriptHostingController = hostingController
    
    // Animate transition
    UIView.transition(
      with: self,
      duration: 0.3,
      options: .transitionFlipFromLeft,
      animations: {
        self.artworkControl.alpha = 0
        hostingController.view.alpha = 1
      }
    )
  }
  
  private func showArtwork() {
    guard let hostingController = transcriptHostingController else { return }
    
    isShowingTranscript = false
    
    // Animate transition
    UIView.transition(
      with: self,
      duration: 0.3,
      options: .transitionFlipFromRight,
      animations: {
        self.artworkControl.alpha = 1
        hostingController.view.alpha = 0
      },
      completion: { _ in
        // Clean up hosting controller
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        self.transcriptHostingController = nil
      }
    )
  }
  
  func updateTranscriptTime(_ time: TimeInterval, viewModel: TranscriptViewerViewModel) {
    guard isShowingTranscript else { return }
    viewModel.updateCurrentTime(time)
  }
  
  func isCurrentlyShowingTranscript() -> Bool {
    return isShowingTranscript
  }
}
