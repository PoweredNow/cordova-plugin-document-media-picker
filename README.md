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
The plugin exposes a single method: DocMediaPicker.showPicker(options) which returns a Promise resolving to an array of selected items.

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

Options
- mode: 'document' | 'media' (default 'document')
- multiple: boolean (default true)
- mimeTypes: string[] (document picker filters; on iOS, accepts UTType identifiers or MIME types on iOS 14+)
- mediaTypes: 'images' | 'videos' | 'all' (default 'all')
- selectionLimit: number (0 = unlimited where supported; default 0)

Notes
- iOS uses PHPicker for media on iOS 14+ and falls back to UIDocumentPicker otherwise.
- Android uses ACTION_OPEN_DOCUMENT for documents and either ACTION_PICK_IMAGES (API 33+, images only) or ACTION_OPEN_DOCUMENT with media filters for media.
- URIs returned by Android's ACTION_PICK_IMAGES are not persisted across restarts; copy the content if you need long-term access.

API Reference
window.DocMediaPicker.showPicker(options) => Promise<Item[]> where Item has the fields described above.