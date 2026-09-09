Document & Media Picker Cordova Plugin

This plugin provides a unified API to pick documents or media (images/videos) on Android and iOS. It wraps the native pickers (UIDocumentPicker/PHPicker on iOS, Storage Access Framework and Media pickers on Android) and returns a normalized array of selected items.

New plugin id: cordova-plugin-document-media-picker
Global JS interface: window.DocMediaPicker

Installation
- Add to your Cordova project:
  cordova plugin add /path/to/packages-native/cordova-plugin-filepicker
  or if published by id:
  cordova plugin add cordova-plugin-document-media-picker

Usage
The plugin exposes DocMediaPicker.showPicker(options) and DocMediaPicker.captureVideo(options). Both methods return a Promise resolving to an array of selected/captured items.

Each item:
- uri: string (content:// or file:// or ios scheme)
- name?: string
- size?: number (bytes)
- mime?: string
- width?: number (images only)
- height?: number (images only)
- createdAt?: number (epoch ms)
- modifiedAt?: number (epoch ms)

Example: pick any document(s)
await DocMediaPicker.showPicker({ mode: 'document', multiple: true, mimeTypes: ['application/pdf', 'image/*'] });

Example: pick images only, up to 5
await DocMediaPicker.showPicker({ mode: 'media', mediaTypes: 'images', selectionLimit: 5 });

Example: capture one video, up to 10 minutes where supported
await DocMediaPicker.captureVideo({ duration: 600 });

Options
- mode: 'document' | 'media' (default 'document')
- multiple: boolean (default true)
- mimeTypes: string[] (document picker filters; on iOS, accepts UTType identifiers or MIME types on iOS 14+)
- mediaTypes: 'images' | 'videos' | 'all' (default 'all')
- selectionLimit: number (0 = unlimited where supported; default 0)
- maxDimension: number (0 = no resizing; default 0)
- convertImageToJpeg: boolean (default true; when false, images are only converted to JPEG if they exceed maxDimension and need resizing)
- duration: number (captureVideo only; maximum duration in seconds where supported, 0 = no limit)

Notes
- iOS uses PHPicker for media on iOS 14+ and falls back to UIDocumentPicker otherwise.
- Android uses ACTION_OPEN_DOCUMENT for documents, either ACTION_PICK_IMAGES (API 33+, images only) or ACTION_OPEN_DOCUMENT with media filters for media, and ACTION_VIDEO_CAPTURE for video capture.
- iOS captureVideo uses the native camera and returns the captured movie file.
- iOS apps that call captureVideo must include NSCameraUsageDescription and NSMicrophoneUsageDescription in Info.plist.
- URIs returned by Android's ACTION_PICK_IMAGES are not persisted across restarts; copy the content if you need long-term access.
- Image selections are converted to JPEG by default. Non-image files such as PDFs are returned unchanged.

API Reference
window.DocMediaPicker.showPicker(options) => Promise<Item[]> where Item has the fields described above.
window.DocMediaPicker.captureVideo(options) => Promise<Item[]> where Item has the fields described above.
