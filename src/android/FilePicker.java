package com.powerednow.filepicker;

import android.app.Activity;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.ext.SdkExtensions;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.text.TextUtils;
import android.webkit.MimeTypeMap;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.ExifInterface;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresExtension;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public class FilePicker extends CordovaPlugin {

    private static final int REQUEST_CODE_DOC = 9812;
    private static final int REQUEST_CODE_MEDIA = 9813;
    private CallbackContext callbackContext;

    private boolean allowMultiple = true;
    private String mode = "document";
    private String mediaTypes = "all"; // images | videos | all
    private String[] mimeTypes = null;
    private int selectionLimit = 0; // 0 = unlimited
    private int maxDimension = 0; // 0 = no resizing

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
        try {
            if (args != null && args.length() > 0) {
                JSONObject opts = args.optJSONObject(0);
                if (opts != null) {
                    this.mode = opts.optString("mode", this.mode);
                    if (opts.has("multiple"))
                        this.allowMultiple = opts.optBoolean("multiple", true);
                    this.mediaTypes = opts.optString("mediaTypes", this.mediaTypes);
                    if (opts.has("selectionLimit"))
                        this.selectionLimit = Math.max(0, opts.optInt("selectionLimit", 0));
                    if (opts.has("maxDimension"))
                        this.maxDimension = Math.max(0, opts.optInt("maxDimension", 0));
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
        } catch (Exception ignored) {
        }
    }

    private void openDocumentPicker() {
        final Activity activity = this.cordova.getActivity();
        Runnable r = () -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            configureIntentMimeTypes(intent, mimeTypes);
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);

            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, (Uri) null);

            cordova.startActivityForResult(FilePicker.this, intent, REQUEST_CODE_DOC);
        };

        if (activity != null) activity.runOnUiThread(r);
        else r.run();
    }

    private void openMediaPicker() {
        final Activity activity = this.cordova.getActivity();
        Runnable r = () -> {
            if (Build.VERSION.SDK_INT >= 33 && "images".equalsIgnoreCase(mediaTypes) && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2) {
                Intent intent = getImagePickIntent();
                cordova.startActivityForResult(FilePicker.this, intent, REQUEST_CODE_MEDIA);
            } else {
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
                intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, (Uri) null);

                cordova.startActivityForResult(FilePicker.this, intent, REQUEST_CODE_DOC);
            }
        };

        if (activity != null) activity.runOnUiThread(r);
        else r.run();
    }

    @RequiresExtension(extension = Build.VERSION_CODES.R, version = 2)
    @NonNull
    private Intent getImagePickIntent() {
        Intent intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
        // NOTE: URIs returned by ACTION_PICK_IMAGES are not persisted across app restarts.
        // If long-term access is needed, copy the content on the JavaScript side using the existing file plugin.
        // Configure multi-select limits per Android requirements:
        // - EXTRA_PICK_IMAGES_MAX must be > 1; setting it to 1 will cause RESULT_CANCELED.
        // - If allowMultiple is true and no explicit limit is given (selectionLimit == 0),
        //   request the system maximum to enable multi-select.
        if (allowMultiple) {
            int max = MediaStore.getPickImagesMaxLimit();
            if (selectionLimit >= 2) {
                intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, Math.min(selectionLimit, max));
            } else if (selectionLimit == 0) {
                intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, max);
            }
            // If selectionLimit == 1, do not set the extra (single-select mode)
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return intent;
    }

    private Uri resizeImageIfNeeded(ContentResolver resolver, Uri imageUri) {
        String mimeType = null;
        try {
            mimeType = resolver.getType(imageUri);
        } catch (Exception ignored) {
        }

        if (mimeType == null || !mimeType.startsWith("image/")) {
            return imageUri;
        }

        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            InputStream inputStream = resolver.openInputStream(imageUri);
            BitmapFactory.decodeStream(inputStream, null, options);
            if (inputStream != null) inputStream.close();

            int originalWidth = options.outWidth;
            int originalHeight = options.outHeight;
            int longestSide = Math.max(originalWidth, originalHeight);

            Bitmap processedBitmap;

            if (maxDimension > 0 && longestSide > maxDimension) {
                float scale = (float) maxDimension / longestSide;
                int newWidth = Math.round(originalWidth * scale);
                int newHeight = Math.round(originalHeight * scale);

                inputStream = resolver.openInputStream(imageUri);
                Bitmap originalBitmap = BitmapFactory.decodeStream(inputStream);
                if (inputStream != null) inputStream.close();

                if (originalBitmap == null) {
                    return imageUri;
                }

                processedBitmap = Bitmap.createScaledBitmap(originalBitmap, newWidth, newHeight, true);
                originalBitmap.recycle();
            } else {
                inputStream = resolver.openInputStream(imageUri);
                processedBitmap = BitmapFactory.decodeStream(inputStream);
                if (inputStream != null) inputStream.close();

                if (processedBitmap == null) {
                    return imageUri;
                }
            }

            File cacheDir = cordova.getContext().getCacheDir();
            String fileName = "resized_" + System.currentTimeMillis() + ".jpg";
            File resizedFile = new File(cacheDir, fileName);

            FileOutputStream outputStream = new FileOutputStream(resizedFile);
            boolean saved = processedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream);
            outputStream.close();
            processedBitmap.recycle();

            if (saved && resizedFile.exists()) {
                try {
                    ExifInterface originalExif = new ExifInterface(resolver.openInputStream(imageUri));
                    ExifInterface newExif = new ExifInterface(resizedFile.getAbsolutePath());

                    copyExifData(originalExif, newExif);

                    newExif.saveAttributes();
                } catch (Exception exifException) {}

                return Uri.fromFile(resizedFile);
            }
        } catch (Exception e) {
            // If anything fails, return the original URI
        }

        return imageUri;
    }

    private void copyExifData(ExifInterface source, ExifInterface destination) {
        String[] exifTags = {
                ExifInterface.TAG_DATETIME,
                ExifInterface.TAG_DATETIME_DIGITIZED,
                ExifInterface.TAG_DATETIME_ORIGINAL,
                ExifInterface.TAG_MAKE,
                ExifInterface.TAG_MODEL,
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.TAG_WHITE_BALANCE,
                ExifInterface.TAG_FOCAL_LENGTH,
                ExifInterface.TAG_FLASH,
                ExifInterface.TAG_IMAGE_LENGTH,
                ExifInterface.TAG_IMAGE_WIDTH,
                ExifInterface.TAG_GPS_LATITUDE,
                ExifInterface.TAG_GPS_LATITUDE_REF,
                ExifInterface.TAG_GPS_LONGITUDE,
                ExifInterface.TAG_GPS_LONGITUDE_REF,
                ExifInterface.TAG_GPS_ALTITUDE,
                ExifInterface.TAG_GPS_ALTITUDE_REF,
                ExifInterface.TAG_GPS_TIMESTAMP,
                ExifInterface.TAG_GPS_DATESTAMP,
                ExifInterface.TAG_EXPOSURE_TIME,
                ExifInterface.TAG_APERTURE_VALUE,
                ExifInterface.TAG_ISO_SPEED_RATINGS,
                ExifInterface.TAG_SUBSEC_TIME,
                ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
                ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
                ExifInterface.TAG_IMAGE_DESCRIPTION,
                ExifInterface.TAG_SOFTWARE,
                ExifInterface.TAG_ARTIST,
                ExifInterface.TAG_COPYRIGHT,
                ExifInterface.TAG_GPS_PROCESSING_METHOD
        };

        for (String tag : exifTags) {
            String value = source.getAttribute(tag);
            if (value != null) {
                destination.setAttribute(tag, value);
            }
        }
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
        boolean tryPersist = requestCode == REQUEST_CODE_DOC;
        JSONArray results = new JSONArray();

        if (data != null) {
            Uri single = data.getData();
            if (single != null) {
                if (tryPersist) {
                    try {
                        resolver.takePersistableUriPermission(single, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    } catch (Exception ignored) {
                    }
                }
                try {
                    results.put(buildFileInfo(resolver, single));
                } catch (JSONException ignored) {
                }
            }
            ClipData clip = data.getClipData();
            if (clip != null) {
                for (int i = 0; i < clip.getItemCount(); i++) {
                    Uri uri = clip.getItemAt(i).getUri();
                    if (uri != null) {
                        if (tryPersist) {
                            try {
                                resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                            } catch (Exception ignored) {
                            }
                        }
                        try {
                            results.put(buildFileInfo(resolver, uri));
                        } catch (JSONException ignored) {
                        }
                    }
                }
            }
        }

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
        Uri finalUri = resizeImageIfNeeded(resolver, uri);

        JSONObject obj = new JSONObject();
        obj.put("uri", finalUri.toString());

        String name = null;
        Long size = null;
        Long dateAdded = null;
        Long dateModified = null;
        Long dateTaken = null;

        try (Cursor cursor = resolver.query(finalUri, new String[]{
                OpenableColumns.DISPLAY_NAME,
                OpenableColumns.SIZE,
                MediaStore.MediaColumns.DATE_ADDED,
                MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.Images.Media.DATE_TAKEN
        }, null, null, null)) {
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
                if (takenIdx != -1 && !cursor.isNull(takenIdx))
                    dateTaken = cursor.getLong(takenIdx);
            }
        } catch (Exception ignored) {
        }

        String mime = null;
        try {
            mime = resolver.getType(finalUri);
        } catch (Exception ignored) {
        }
        if (mime == null) {
            String ext = MimeTypeMap.getFileExtensionFromUrl(finalUri.toString());
            if (TextUtils.isEmpty(ext) && name != null) {
                int dot = name.lastIndexOf('.');
                if (dot != -1) ext = name.substring(dot + 1);
            }
            if (!TextUtils.isEmpty(ext)) {
                mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.toLowerCase());
            }
        }

        if (name == null) name = finalUri.getLastPathSegment();
        if (name != null) obj.put("name", name);
        if (size != null) obj.put("size", size);
        if (mime != null) obj.put("mime", mime);

        String fileExtension = null;
        if (!TextUtils.isEmpty(name)) {
            int dot = name.lastIndexOf('.');
            if (dot > 0 && dot < name.length() - 1) {
                fileExtension = name.substring(dot + 1).toLowerCase();
            }
        }
        if (TextUtils.isEmpty(fileExtension) && !TextUtils.isEmpty(mime)) {
            String fromMime = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime);
            if (!TextUtils.isEmpty(fromMime)) {
                fileExtension = fromMime.toLowerCase();
                if ("jpeg".equals(fileExtension)) fileExtension = "jpg";
            }
        }
        if (TextUtils.isEmpty(fileExtension)) {
            String fromUri = MimeTypeMap.getFileExtensionFromUrl(finalUri.toString());
            if (!TextUtils.isEmpty(fromUri)) fileExtension = fromUri.toLowerCase();
        }
        if (!TextUtils.isEmpty(fileExtension)) {
            obj.put("fileExtension", fileExtension);
        }

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
        if (createdAt != null && createdAt < 1000000000000L) createdAt = createdAt * 1000L;
        if (modifiedAt != null && modifiedAt < 1000000000000L) modifiedAt = modifiedAt * 1000L;
        if (createdAt != null) obj.put("createdAt", createdAt);
        if (modifiedAt != null) obj.put("modifiedAt", modifiedAt);

        if (mime != null && mime.startsWith("image/")) {
            InputStream is = null;
            try {
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inJustDecodeBounds = true;
                is = resolver.openInputStream(finalUri);
                BitmapFactory.decodeStream(is, null, options);
                if (options.outWidth > 0 && options.outHeight > 0) {
                    obj.put("width", options.outWidth);
                    obj.put("height", options.outHeight);
                }
            } catch (Exception ignored) {
            } finally {
                if (is != null) {
                    try {
                        is.close();
                    } catch (Exception ignored) {
                    }
                }
            }
        }

        return obj;
    }
}
