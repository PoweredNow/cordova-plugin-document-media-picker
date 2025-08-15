package com.powerednow.filepicker;
a
import android.app.Activity;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.text.TextUtils;
import android.webkit.MimeTypeMap;
import android.graphics.BitmapFactory;
import java.io.InputStream;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public class FilePicker extends CordovaPlugin {

    private static final int REQUEST_CODE_DOC = 9812;
    private static final int REQUEST_CODE_MEDIA = 9813;
    private CallbackContext callbackContext;

    // Options
    private boolean allowMultiple = true;
    private String mode = "document";
    private String mediaTypes = "all"; // images | videos | all
    private String[] mimeTypes = null;
    private int selectionLimit = 0; // 0 = unlimited

    @Override
    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        super.initialize(cordova, webView);
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) {
        if ("showPicker".equals(action)) {
            this.callbackContext = callbackContext;
            parseOptions(args);
            if ("media".equalsIgnoreCase(mode)) {
                openMediaPicker();
            } else {
                openDocumentPicker();
            }
            return true;
        }
        return false;
    }

    private void parseOptions(JSONArray args) {
        // defaults already set
        try {
            if (args != null && args.length() > 0) {
                JSONObject opts = args.optJSONObject(0);
                if (opts != null) {
                    this.mode = opts.optString("mode", this.mode);
                    if (opts.has("multiple")) this.allowMultiple = opts.optBoolean("multiple", true);
                    this.mediaTypes = opts.optString("mediaTypes", this.mediaTypes);
                    if (opts.has("selectionLimit")) this.selectionLimit = Math.max(0, opts.optInt("selectionLimit", 0));
                    JSONArray mt = opts.optJSONArray("mimeTypes");
                    if (mt != null && mt.length() > 0) {
                        this.mimeTypes = new String[mt.length()];
                        for (int i = 0; i < mt.length(); i++) {
                            this.mimeTypes[i] = mt.optString(i);
                        }
                    } else {
                        this.mimeTypes = null;
                    }
                }
            }
        } catch (Exception ignored) {}
    }

    private void openDocumentPicker() {
        final Activity activity = this.cordova.getActivity();
        Runnable r = new Runnable() {
            @Override
            public void run() {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                configureIntentMimeTypes(intent, mimeTypes);
                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple);
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, (Uri) null);
                }

                cordova.setActivityResultCallback(FilePicker.this);
                cordova.startActivityForResult(FilePicker.this, intent, REQUEST_CODE_DOC);
            }
        };

        if (activity != null) activity.runOnUiThread(r); else r.run();
    }

    private void openMediaPicker() {
        final Activity activity = this.cordova.getActivity();
        Runnable r = new Runnable() {
            @Override
            public void run() {
                if (Build.VERSION.SDK_INT >= 33 && "images".equalsIgnoreCase(mediaTypes)) {
                    Intent intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
                    // NOTE: URIs returned by ACTION_PICK_IMAGES are not persisted across app restarts.
                    // If long-term access is needed, copy the content on the JavaScript side using the existing file plugin.
                    if (selectionLimit > 0) {
                        intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, selectionLimit);
                    } else if (!allowMultiple) {
                        intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 1);
                    }
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    cordova.setActivityResultCallback(FilePicker.this);
                    cordova.startActivityForResult(FilePicker.this, intent, REQUEST_CODE_MEDIA);
                } else {
                    // Fallback to ACTION_OPEN_DOCUMENT with media filters
                    String[] types;
                    if ("images".equalsIgnoreCase(mediaTypes)) {
                        types = new String[]{"image/*"};
                    } else if ("videos".equalsIgnoreCase(mediaTypes)) {
                        types = new String[]{"video/*"};
                    } else {
                        types = new String[]{"image/*", "video/*"};
                    }
                    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    configureIntentMimeTypes(intent, types);
                    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple);
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, (Uri) null);
                    }
                    cordova.setActivityResultCallback(FilePicker.this);
                    cordova.startActivityForResult(FilePicker.this, intent, REQUEST_CODE_DOC);
                }
            }
        };

        if (activity != null) activity.runOnUiThread(r); else r.run();
    }

    private void configureIntentMimeTypes(Intent intent, String[] types) {
        if (types == null || types.length == 0) {
            intent.setType("*/*");
            return;
        }
        if (types.length == 1) {
            intent.setType(types[0]);
        } else {
            intent.setType("*/*");
            intent.putExtra(Intent.EXTRA_MIME_TYPES, types);
        }
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_CODE_DOC && requestCode != REQUEST_CODE_MEDIA) return;

        if (resultCode == Activity.RESULT_CANCELED) {
            if (callbackContext != null) {
                callbackContext.success(new JSONArray());
                callbackContext = null;
            }
            return;
        }

        if (resultCode != Activity.RESULT_OK) {
            if (callbackContext != null) {
                callbackContext.error("FAILED");
                callbackContext = null;
            }
            return;
        }

        ContentResolver resolver = cordova.getContext().getContentResolver();
        boolean tryPersist = requestCode == REQUEST_CODE_DOC; // only for OPEN_DOCUMENT
        JSONArray results = new JSONArray();

        if (data != null) {
            int takeFlags = data.getFlags() & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);

            Uri single = data.getData();
            if (single != null) {
                if (tryPersist) {
                    try { resolver.takePersistableUriPermission(single, takeFlags); } catch (Exception ignored) {}
                }
                try { results.put(buildFileInfo(resolver, single)); } catch (JSONException ignored) {}
            }
            ClipData clip = data.getClipData();
            if (clip != null) {
                for (int i = 0; i < clip.getItemCount(); i++) {
                    Uri uri = clip.getItemAt(i).getUri();
                    if (uri != null) {
                        if (tryPersist) {
                            try { resolver.takePersistableUriPermission(uri, takeFlags); } catch (Exception ignored) {}
                        }
                        try { results.put(buildFileInfo(resolver, uri)); } catch (JSONException ignored) {}
                    }
                }
            }
        }

        // Enforce selection limit if provided
        if (selectionLimit > 0 && results.length() > selectionLimit) {
            JSONArray trimmed = new JSONArray();
            for (int i = 0; i < selectionLimit; i++) {
                trimmed.put(results.opt(i));
            }
            results = trimmed;
        }

        if (callbackContext != null) {
            callbackContext.success(results);
            callbackContext = null;
        }
    }

    private JSONObject buildFileInfo(ContentResolver resolver, Uri uri) throws JSONException {
        JSONObject obj = new JSONObject();
        obj.put("uri", uri.toString());

        String name = null;
        Long size = null;
        Long dateAdded = null;
        Long dateModified = null;
        Long dateTaken = null;

        Cursor cursor = null;
        try {
            cursor = resolver.query(uri, new String[]{
                    OpenableColumns.DISPLAY_NAME,
                    OpenableColumns.SIZE,
                    MediaStore.MediaColumns.DATE_ADDED,
                    MediaStore.MediaColumns.DATE_MODIFIED,
                    MediaStore.Images.Media.DATE_TAKEN
            }, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (nameIdx != -1) name = cursor.getString(nameIdx);
                int sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE);
                if (sizeIdx != -1 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx);
                int addIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_ADDED);
                if (addIdx != -1 && !cursor.isNull(addIdx)) dateAdded = cursor.getLong(addIdx);
                int modIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED);
                if (modIdx != -1 && !cursor.isNull(modIdx)) dateModified = cursor.getLong(modIdx);
                int takenIdx = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN);
                if (takenIdx != -1 && !cursor.isNull(takenIdx)) dateTaken = cursor.getLong(takenIdx);
            }
        } catch (Exception ignored) {
        } finally {
            if (cursor != null) cursor.close();
        }

        String mime = null;
        try { mime = resolver.getType(uri); } catch (Exception ignored) {}
        if (mime == null) {
            String ext = MimeTypeMap.getFileExtensionFromUrl(uri.toString());
            if (TextUtils.isEmpty(ext) && name != null) {
                int dot = name.lastIndexOf('.');
                if (dot != -1) ext = name.substring(dot + 1);
            }
            if (!TextUtils.isEmpty(ext)) {
                mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.toLowerCase());
            }
        }

        if (name == null) name = uri.getLastPathSegment();
        if (name != null) obj.put("name", name);
        if (size != null) obj.put("size", size);
        if (mime != null) obj.put("mime", mime);

        // Dates
        Long createdAt = null;
        Long modifiedAt = null;
        if (dateTaken != null && dateTaken > 0) {
            createdAt = dateTaken;
        } else if (dateAdded != null && dateAdded > 0) {
            createdAt = dateAdded;
        }
        if (dateModified != null && dateModified > 0) {
            modifiedAt = dateModified;
        }
        // Convert seconds to ms if needed
        if (createdAt != null && createdAt < 1000000000000L) createdAt = createdAt * 1000L;
        if (modifiedAt != null && modifiedAt < 1000000000000L) modifiedAt = modifiedAt * 1000L;
        if (createdAt != null) obj.put("createdAt", createdAt);
        if (modifiedAt != null) obj.put("modifiedAt", modifiedAt);

        // Image dimensions
        if (mime != null && mime.startsWith("image/")) {
            InputStream is = null;
            try {
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inJustDecodeBounds = true;
                is = resolver.openInputStream(uri);
                BitmapFactory.decodeStream(is, null, options);
                if (options.outWidth > 0 && options.outHeight > 0) {
                    obj.put("width", options.outWidth);
                    obj.put("height", options.outHeight);
                }
            } catch (Exception ignored) {
            } finally {
                if (is != null) {
                    try { is.close(); } catch (Exception ignored) {}
                }
            }
        }

        return obj;
    }
}
