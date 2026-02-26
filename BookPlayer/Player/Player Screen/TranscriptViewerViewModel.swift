//
//  TranscriptViewerViewModel.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import Foundation
import Combine
import BookPlayerKit

/// ViewModel for the synchronized transcript viewer
class TranscriptViewerViewModel: ObservableObject {
  @Published var lrcDocument: LRCDocument?
  @Published var currentLineIndex: Int?
  @Published var currentTime: TimeInterval = 0
  
  private var cancellables = Set<AnyCancellable>()
  
  var lines: [LRCLine] {
    return lrcDocument?.lines ?? []
  }
  
  var hasTranscript: Bool {
    return lrcDocument != nil
  }
  
  /// Update the current playback time and find the corresponding line
  func updateCurrentTime(_ time: TimeInterval) {
    currentTime = time
    
    guard let document = lrcDocument else {
      currentLineIndex = nil
      return
    }
    
    currentLineIndex = document.getLineIndex(for: time)
  }
  
  /// Load an LRC document for the current item
  func loadTranscript(for relativePath: String) {
    lrcDocument = LRCService.shared.loadLRCDocument(for: relativePath)
    updateCurrentTime(currentTime)
  }
  
  /// Clear the current transcript
  func clearTranscript() {
    lrcDocument = nil
    currentLineIndex = nil
  }
  
  /// Check if a transcript exists for the given item
  func hasTranscript(for relativePath: String) -> Bool {
    return LRCService.shared.hasLRCFile(for: relativePath)
  }
}
