//
//  TranscriptImporter.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers
import BookPlayerKit

/// Handles importing LRC transcript files
class TranscriptImporter: NSObject {
  
  private weak var presentingViewController: UIViewController?
  private var relativePath: String?
  private var onImportComplete: ((Result<Void, Error>) -> Void)?
  
  init(presentingViewController: UIViewController) {
    self.presentingViewController = presentingViewController
    super.init()
  }
  
  /// Present file picker to import an LRC file
  func importTranscript(
    for relativePath: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    self.relativePath = relativePath
    self.onImportComplete = completion
    
    presentFilePicker()
  }
  
  private func presentFilePicker() {
    guard let viewController = presentingViewController else {
      onImportComplete?(.failure(TranscriptImporterError.noViewController))
      return
    }
    
    let documentPicker: UIDocumentPickerViewController
    
    if #available(iOS 14.0, *) {
      // Use UTType for iOS 14+
      let lrcType = UTType(filenameExtension: "lrc") ?? .text
      documentPicker = UIDocumentPickerViewController(
        forOpeningContentTypes: [lrcType],
        asCopy: true
      )
    } else {
      // Fallback for earlier iOS versions
      documentPicker = UIDocumentPickerViewController(
        documentTypes: ["public.text", "public.plain-text"],
        in: .import
      )
    }
    
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    documentPicker.modalPresentationStyle = .formSheet
    
    viewController.present(documentPicker, animated: true)
  }
  
  private func handleSelectedFile(url: URL) {
    guard let relativePath = relativePath else {
      onImportComplete?(.failure(TranscriptImporterError.invalidState))
      return
    }
    
    // Ensure we have access to the file
    guard url.startAccessingSecurityScopedResource() else {
      onImportComplete?(.failure(TranscriptImporterError.accessDenied))
      return
    }
    
    defer {
      url.stopAccessingSecurityScopedResource()
    }
    
    do {
      // Import the LRC file using the service
      try LRCService.shared.importLRCFile(from: url, for: relativePath)
      onImportComplete?(.success(()))
    } catch let error as LRCParserError {
      onImportComplete?(.failure(error))
    } catch {
      onImportComplete?(.failure(TranscriptImporterError.importFailed(error)))
    }
  }
}

// MARK: - UIDocumentPickerDelegate
extension TranscriptImporter: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else {
      onImportComplete?(.failure(TranscriptImporterError.noFileSelected))
      return
    }
    
    handleSelectedFile(url: url)
  }
  
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    onImportComplete?(.failure(TranscriptImporterError.cancelled))
  }
}

// MARK: - Errors
enum TranscriptImporterError: Error, LocalizedError {
  case noViewController
  case invalidState
  case accessDenied
  case noFileSelected
  case cancelled
  case importFailed(Error)
  
  var errorDescription: String? {
    switch self {
    case .noViewController:
      return "No view controller available to present file picker."
    case .invalidState:
      return "Invalid state: no relative path set."
    case .accessDenied:
      return "Access to the selected file was denied."
    case .noFileSelected:
      return "No file was selected."
    case .cancelled:
      return "Import was cancelled."
    case .importFailed(let error):
      return "Import failed: \(error.localizedDescription)"
    }
  }
}
