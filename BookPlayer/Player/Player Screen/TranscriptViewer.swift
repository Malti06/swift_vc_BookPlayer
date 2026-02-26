//
//  TranscriptViewer.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import SwiftUI
import BookPlayerKit

/// SwiftUI view for displaying synchronized transcript text
struct TranscriptViewer: View {
  @ObservedObject var viewModel: TranscriptViewerViewModel
  let onLineTap: (TimeInterval) -> Void
  
  @State private var scrollTarget: UUID?
  
  var body: some View {
    ZStack {
      // Background gradient matching the artwork control
      LinearGradient(
        gradient: Gradient(colors: [
          Color(UIColor.systemBackground.withAlphaComponent(0.95)),
          Color(UIColor.systemBackground.withAlphaComponent(0.98))
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      
      if viewModel.hasTranscript {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(Array(viewModel.lines.enumerated()), id: \.element.id) { index, line in
                TranscriptLineView(
                  line: line,
                  isActive: index == viewModel.currentLineIndex,
                  onTap: {
                    onLineTap(line.timestamp)
                  }
                )
                .id(line.id)
              }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)  // Add top padding to avoid button area
            .padding(.bottom, 16)
          }
          .onChange(of: viewModel.currentLineIndex) { newIndex in
            guard let newIndex = newIndex,
                  newIndex < viewModel.lines.count else { return }
            
            let line = viewModel.lines[newIndex]
            withAnimation(.easeOut(duration: 0.3)) {
              proxy.scrollTo(line.id, anchor: .center)
            }
          }
        }
        .allowsHitTesting(true)  // Enable hit testing for the scroll view
      } else {
        // Empty state
        VStack(spacing: 16) {
          Image(systemName: "doc.text")
            .font(.system(size: 60))
            .foregroundColor(.secondary)
          
          Text("No Transcript Available")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
          
          Text("Import an .lrc file to see the transcript here")
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
        }
      }
    }
  }
}

/// Individual line view in the transcript
struct TranscriptLineView: View {
  let line: LRCLine
  let isActive: Bool
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      // Text content only (no timestamp)
      Text(line.text.isEmpty ? "♪" : line.text)
        .font(.body)
        .fontWeight(isActive ? .semibold : .regular)
        .foregroundColor(isActive ? .white : .primary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(isActive ? Color.accentColor : Color.clear)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    .buttonStyle(PlainButtonStyle())
    .padding(.vertical, 2)
  }
}

// Preview support
#if DEBUG
struct TranscriptViewer_Previews: PreviewProvider {
  static var previews: some View {
    let viewModel = TranscriptViewerViewModel()
    
    // Create sample data
    let sampleLines = [
      LRCLine(timestamp: 0, text: "This is the first line of the transcript"),
      LRCLine(timestamp: 5.5, text: "This is the second line with more text"),
      LRCLine(timestamp: 12.0, text: "Third line here"),
      LRCLine(timestamp: 18.5, text: "And the fourth line continues the story"),
      LRCLine(timestamp: 25.0, text: "Fifth line with even more content to display"),
    ]
    
    viewModel.lrcDocument = LRCDocument(
      metadata: LRCMetadata(),
      lines: sampleLines
    )
    viewModel.currentLineIndex = 2
    
    return TranscriptViewer(
      viewModel: viewModel,
      onLineTap: { time in
        print("Tapped line at \(time)")
      }
    )
  }
}
#endif
