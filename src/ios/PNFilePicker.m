#import "PNFilePicker.h"

static NSString * const PNFilePickerJpegConversionErrorDomain = @"PNFilePickerJpegConversionError";

@interface PNFilePicker ()
@end

@implementation PNFilePicker

- (void)showPicker:(CDVInvokedUrlCommand*)command
{
    self.callbackId = command.callbackId;
    id firstArg = command.arguments.count > 0 ? command.arguments[0] : nil;
    if ([firstArg isKindOfClass:[NSDictionary class]]) {
        self.options = (NSDictionary *)firstArg;
    } else {
        self.options = @{};
    }

    // selection limit (0 = unlimited)
    NSNumber *sel = self.options[@"selectionLimit"];
    self.selectionLimit = sel ? MAX(0, sel.integerValue) : 0;

    NSString *mode = [[self.options objectForKey:@"mode"] isKindOfClass:[NSString class]] ? self.options[@"mode"] : @"document";
    BOOL multiple = self.options[@"multiple"] ? [self.options[@"multiple"] boolValue] : YES;

    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([mode.lowercaseString isEqualToString:@"media"]) {
            // Media picker via PHPicker
            if (@available(iOS 14.0, *)) {
                PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
                NSString *mediaTypes = [[weakSelf.options objectForKey:@"mediaTypes"] isKindOfClass:[NSString class]] ? weakSelf.options[@"mediaTypes"] : @"all";
                if ([mediaTypes.lowercaseString isEqualToString:@"images"]) {
                    config.filter = [PHPickerFilter imagesFilter];
                } else if ([mediaTypes.lowercaseString isEqualToString:@"videos"]) {
                    config.filter = [PHPickerFilter videosFilter];
                } else {
                    config.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[[PHPickerFilter imagesFilter], [PHPickerFilter videosFilter]]];
                }
                config.selectionLimit = weakSelf.selectionLimit > 0 ? weakSelf.selectionLimit : (multiple ? 0 : 1);

                PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
                picker.delegate = weakSelf;
                picker.modalPresentationStyle = UIModalPresentationFormSheet;

                UIViewController *vc = weakSelf.viewController;
                while (vc.presentedViewController) { vc = vc.presentedViewController; }
                [vc presentViewController:picker animated:YES completion:nil];
            } else {
                [weakSelf presentDocumentPickerAllowMultiple:multiple];
            }
        } else {
            [weakSelf presentDocumentPickerAllowMultiple:multiple];
        }
    });
}

- (void)captureVideo:(CDVInvokedUrlCommand*)command
{
    self.callbackId = command.callbackId;
    id firstArg = command.arguments.count > 0 ? command.arguments[0] : nil;
    if ([firstArg isKindOfClass:[NSDictionary class]]) {
        self.options = (NSDictionary *)firstArg;
    } else {
        self.options = @{};
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Video capture is not available on this device."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
        return;
    }

    NSArray<NSString *> *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
    if (![availableMediaTypes containsObject:@"public.movie"]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Video capture is not available on this device."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
        return;
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ @"public.movie" ];
        picker.delegate = weakSelf;
        picker.videoQuality = UIImagePickerControllerQualityTypeHigh;

        NSNumber *duration = weakSelf.options[@"duration"];
        if ([duration respondsToSelector:@selector(doubleValue)] && duration.doubleValue > 0) {
            picker.videoMaximumDuration = duration.doubleValue;
        }

        UIViewController *vc = weakSelf.viewController;
        while (vc.presentedViewController) { vc = vc.presentedViewController; }
        [vc presentViewController:picker animated:YES completion:nil];
    });
}

- (void)presentDocumentPickerAllowMultiple:(BOOL)multiple
{
    NSArray<NSString *> *types = [self documentTypesFromOptions:self.options];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
    if ([picker respondsToSelector:@selector(setAllowsMultipleSelection:)]) {
        picker.allowsMultipleSelection = multiple;
    }
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;

    UIViewController *vc = self.viewController;
    while (vc.presentedViewController) { vc = vc.presentedViewController; }
    [vc presentViewController:picker animated:YES completion:nil];
}

- (NSArray<NSString *> *)documentTypesFromOptions:(NSDictionary *)opts
{
    id mimes = opts[@"mimeTypes"];
    if ([mimes isKindOfClass:[NSArray class]] && [mimes count] > 0) {
        NSMutableArray<NSString *> *docTypes = [NSMutableArray array];
        for (id item in (NSArray *)mimes) {
            if (![item isKindOfClass:[NSString class]]) continue;
            NSString *s = (NSString *)item;
            if ([s containsString:@"/"]) {
                if (@available(iOS 14.0, *)) {
                    NSArray<UTType *> *types = [UTType typesWithTag:s tagClass:UTTagClassMIMEType conformingToType:nil];
                    if (types.count > 0) {
                        UTType *t = types.firstObject;
                        if (t.identifier) [docTypes addObject:t.identifier];
                    }
                }
            } else {
                [docTypes addObject:s];
            }
        }
        if (docTypes.count > 0) return docTypes;
    }
    return @[ @"public.data" ];
}

- (NSError *)jpegConversionErrorWithMessage:(NSString *)message underlyingError:(NSError *)underlyingError
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = message ?: @"JPEG_CONVERSION_FAILED";
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:PNFilePickerJpegConversionErrorDomain code:1 userInfo:userInfo];
}

- (void)sendJpegConversionError:(NSError *)error
{
    NSString *message = error.localizedDescription ?: @"JPEG_CONVERSION_FAILED";
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    self.callbackId = nil;
}

- (BOOL)urlLooksLikeImage:(NSURL *)url
{
    NSString *ext = url.pathExtension.lowercaseString;

    if (@available(iOS 14.0, *)) {
        NSDictionary<NSURLResourceKey, id> *values = [url resourceValuesForKeys:@[NSURLContentTypeKey] error:nil];
        UTType *contentType = values[NSURLContentTypeKey];
        if ([contentType isKindOfClass:[UTType class]] && [contentType conformsToType:UTTypeImage]) {
            return YES;
        }

        if (ext.length > 0) {
            UTType *type = [UTType typeWithFilenameExtension:ext];
            if (type && [type conformsToType:UTTypeImage]) {
                return YES;
            }
        }
    }

    if (ext.length == 0) return NO;

    static NSSet<NSString *> *imageExtensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageExtensions = [NSSet setWithArray:@[
            @"jpg", @"jpeg", @"png", @"gif", @"heic", @"heif", @"webp", @"bmp", @"tif", @"tiff"
        ]];
    });
    return [imageExtensions containsObject:ext];
}

- (BOOL)shouldConvertImageToJpeg
{
    id option = self.options[@"convertImageToJpeg"];
    return [option respondsToSelector:@selector(boolValue)] ? [option boolValue] : YES;
}

- (NSURL *)uniqueJpegURLForImageURL:(NSURL *)imageURL resized:(BOOL)resized
{
    NSString *originalPath = imageURL.path;
    NSString *baseName = [[originalPath lastPathComponent] stringByDeletingPathExtension];
    if (baseName.length == 0) {
        baseName = [NSUUID UUID].UUIDString;
    }
    NSString *directory = [originalPath stringByDeletingLastPathComponent];
    NSString *suffix = resized ? @"resized" : @"converted";
    NSString *newFileName = [NSString stringWithFormat:@"%@_%@.jpg", baseName, suffix];
    NSString *newPath = [directory stringByAppendingPathComponent:newFileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger index = 1;
    while ([fm fileExistsAtPath:newPath]) {
        newFileName = [NSString stringWithFormat:@"%@_%@_%ld.jpg", baseName, suffix, (long)index];
        newPath = [directory stringByAppendingPathComponent:newFileName];
        index++;
    }

    return [NSURL fileURLWithPath:newPath];
}

- (NSURL *)uniqueCacheURLForFileName:(NSString *)fileName
{
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *safeFileName = fileName.length > 0 ? fileName : [[NSUUID UUID] UUIDString];
    if (safeFileName.pathExtension.length == 0) {
        safeFileName = [safeFileName stringByAppendingPathExtension:@"MOV"];
    }

    NSString *destPath = [cacheDir stringByAppendingPathComponent:safeFileName];
    NSInteger suffix = 1;
    NSString *baseName = [safeFileName stringByDeletingPathExtension];
    NSString *ext = [safeFileName pathExtension];
    NSFileManager *fm = [NSFileManager defaultManager];

    while ([fm fileExistsAtPath:destPath]) {
        NSString *candidate = ext.length > 0 ? [NSString stringWithFormat:@"%@ (%ld).%@", baseName, (long)suffix, ext] : [NSString stringWithFormat:@"%@ (%ld)", baseName, (long)suffix];
        destPath = [cacheDir stringByAppendingPathComponent:candidate];
        suffix++;
    }

    return [NSURL fileURLWithPath:destPath];
}

- (NSURL *)convertImageToJpegIfNeeded:(NSURL *)imageURL knownImage:(BOOL)knownImage error:(NSError **)error
{
    BOOL shouldProcess = knownImage || [self urlLooksLikeImage:imageURL];
    if (!shouldProcess) {
        return imageURL;
    }

    BOOL convertOption = [self shouldConvertImageToJpeg];
    CGFloat maxDimension = 0;
    NSNumber *maxDimensionOption = self.options[@"maxDimension"];
    if ([maxDimensionOption isKindOfClass:[NSNumber class]]) {
        maxDimension = MAX(0, maxDimensionOption.floatValue);
    }

    if (!convertOption && maxDimension <= 0) {
        return imageURL;
    }

    UIImage *originalImage = [UIImage imageWithContentsOfFile:imageURL.path];
    if (!originalImage) {
        if (convertOption && error) {
            *error = [self jpegConversionErrorWithMessage:@"JPEG_CONVERSION_FAILED: Unable to decode selected image" underlyingError:nil];
        }
        return convertOption ? nil : imageURL;
    }

    UIImage *outputImage = originalImage;
    CGFloat originalWidth = originalImage.size.width;
    CGFloat originalHeight = originalImage.size.height;
    CGFloat longestSide = MAX(originalWidth, originalHeight);
    BOOL resized = maxDimension > 0 && longestSide > maxDimension;
    BOOL shouldConvert = convertOption || resized;

    if (!shouldConvert) {
        return imageURL;
    }

    if (resized) {
        CGFloat scale = maxDimension / longestSide;
        CGFloat newWidth = MAX(1.0, originalWidth * scale);
        CGFloat newHeight = MAX(1.0, originalHeight * scale);
        CGSize newSize = CGSizeMake(newWidth, newHeight);

        UIGraphicsBeginImageContextWithOptions(newSize, YES, 1.0);
        [[UIColor whiteColor] setFill];
        UIRectFill(CGRectMake(0, 0, newWidth, newHeight));
        [originalImage drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
        outputImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!outputImage) {
            if (error) {
                *error = [self jpegConversionErrorWithMessage:@"JPEG_CONVERSION_FAILED: Unable to resize selected image" underlyingError:nil];
            }
            return nil;
        }
    }

    NSData *jpegData = UIImageJPEGRepresentation(outputImage, 0.9);
    if (!jpegData) {
        if (error) {
            *error = [self jpegConversionErrorWithMessage:@"JPEG_CONVERSION_FAILED: Unable to encode selected image as JPEG" underlyingError:nil];
        }
        return nil;
    }

    NSURL *jpegURL = [self uniqueJpegURLForImageURL:imageURL resized:resized];
    NSError *writeError = nil;
    if (![jpegData writeToURL:jpegURL options:NSDataWritingAtomic error:&writeError]) {
        if (error) {
            *error = [self jpegConversionErrorWithMessage:@"JPEG_CONVERSION_FAILED: Unable to write JPEG image" underlyingError:writeError];
        }
        return nil;
    }

    [[NSFileManager defaultManager] removeItemAtURL:imageURL error:nil];
    return jpegURL;
}

- (NSDictionary *)buildFileInfoForURL:(NSURL *)url
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (!url) return info;
    info[@"uri"] = url.absoluteString ?: @"";
    NSString *name = url.lastPathComponent ?: @"";
    if (name) info[@"name"] = name;

    NSError *attrErr = nil;
    NSDictionary<NSFileAttributeKey, id> *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:&attrErr];
    if (attrs) {
        NSNumber *size = attrs[NSFileSize];
        if (size) info[@"size"] = size;
        NSDate *creation = attrs[NSFileCreationDate];
        NSDate *modif = attrs[NSFileModificationDate];
        if (creation) info[@"createdAt"] = @((long long)([creation timeIntervalSince1970] * 1000.0));
        if (modif) info[@"modifiedAt"] = @((long long)([modif timeIntervalSince1970] * 1000.0));
    }

    NSString *ext = url.pathExtension.lowercaseString;
    if (@available(iOS 14.0, *)) {
        if (ext.length > 0) {
            UTType *type = [UTType typeWithFilenameExtension:ext];
            if (type.preferredMIMEType) {
                info[@"mime"] = type.preferredMIMEType;
            }
        }
    }
    if (!info[@"mime"]) {
        if ([@[ @"jpg", @"jpeg" ] containsObject:ext]) info[@"mime"] = @"image/jpeg";
        else if ([ext isEqualToString:@"png"]) info[@"mime"] = @"image/png";
        else if ([ext isEqualToString:@"gif"]) info[@"mime"] = @"image/gif";
        else if ([ext isEqualToString:@"pdf"]) info[@"mime"] = @"application/pdf";
    }

    @try {
        UIImage *img = [UIImage imageWithContentsOfFile:url.path];
        if (img) {
            CGFloat width = img.size.width * img.scale;
            CGFloat height = img.size.height * img.scale;
            if (width > 0 && height > 0) {
                info[@"width"] = @((NSInteger)width);
                info[@"height"] = @((NSInteger)height);
            }
        }
    } @catch (NSException *exception) {
        // ignore
    }

    return info;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:urls.count];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSError *conversionFailure = nil;

    for (NSURL *url in urls) {
        BOOL accessStarted = [url startAccessingSecurityScopedResource];
        @try {
            NSString *fileName = url.lastPathComponent ? url.lastPathComponent : [[NSUUID UUID] UUIDString];
            NSString *destPath = [cacheDir stringByAppendingPathComponent:fileName];
            NSURL *destURL = [NSURL fileURLWithPath:destPath];

            NSInteger suffix = 1;
            NSString *baseName = [fileName stringByDeletingPathExtension];
            NSString *ext = [fileName pathExtension];
            while ([fm fileExistsAtPath:destPath]) {
                NSString *candidate = ext.length > 0 ? [NSString stringWithFormat:@"%@ (%ld).%@", baseName, (long)suffix, ext] : [NSString stringWithFormat:@"%@ (%ld)", baseName, (long)suffix];
                destPath = [cacheDir stringByAppendingPathComponent:candidate];
                destURL = [NSURL fileURLWithPath:destPath];
                suffix++;
            }

            NSError *err = nil;
            if (![fm copyItemAtURL:url toURL:destURL error:&err]) {
                if (err) {
                    NSData *data = [NSData dataWithContentsOfURL:url];
                    if (data) {
                        [data writeToURL:destURL atomically:YES];
                        err = nil;
                    }
                }
            }

            if (!err && [fm fileExistsAtPath:destPath]) {
                NSError *conversionError = nil;
                NSURL *finalURL = [self convertImageToJpegIfNeeded:destURL knownImage:NO error:&conversionError];
                if (conversionError) {
                    conversionFailure = conversionError;
                }

                NSDictionary *info = conversionFailure ? nil : [self buildFileInfoForURL:finalURL];
                if (info) [result addObject:info];
            }
        } @catch (NSException *exception) {
            // ignore individual file failure
        } @finally {
            if (accessStarted) {
                [url stopAccessingSecurityScopedResource];
            }
        }

        if (conversionFailure) {
            [self sendJpegConversionError:conversionFailure];
            return;
        }
    }

    if (self.selectionLimit > 0 && result.count > self.selectionLimit) {
        NSRange range = NSMakeRange(self.selectionLimit, result.count - self.selectionLimit);
        [result removeObjectsInRange:range];
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    self.callbackId = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    self.callbackId = nil;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info
{
    [picker dismissViewControllerAnimated:YES completion:nil];

    NSURL *mediaURL = info[UIImagePickerControllerMediaURL];
    if (!mediaURL) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No video was captured."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
        return;
    }

    NSString *fileName = mediaURL.lastPathComponent ?: [[NSUUID UUID] UUIDString];
    NSURL *destURL = [self uniqueCacheURLForFileName:fileName];
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtURL:mediaURL toURL:destURL error:&copyError]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unable to prepare captured video."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
        return;
    }

    NSMutableDictionary *fileInfo = [[self buildFileInfoForURL:destURL] mutableCopy];
    if (!fileInfo[@"mime"]) {
        fileInfo[@"mime"] = @"video/quicktime";
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[fileInfo]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    self.callbackId = nil;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    self.callbackId = nil;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0))
{
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (results.count == 0) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
        return;
    }

    NSMutableArray *collected = [NSMutableArray arrayWithCapacity:results.count];
    dispatch_group_t group = dispatch_group_create();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    __block NSError *conversionFailure = nil;

    for (PHPickerResult *res in results) {
        NSItemProvider *provider = res.itemProvider;
        NSString *typeToLoad = nil;
        if ([provider hasItemConformingToTypeIdentifier:@"public.image"]) {
            typeToLoad = @"public.image";
        } else if ([provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
            typeToLoad = @"public.movie";
        } else if (provider.registeredTypeIdentifiers.firstObject) {
            typeToLoad = provider.registeredTypeIdentifiers.firstObject;
        }
        if (!typeToLoad) continue;

        UTType *ut = nil;
        NSString *derivedExt = nil;
        NSString *derivedMime = nil;
        if (@available(iOS 14.0, *)) {
            ut = [UTType typeWithIdentifier:typeToLoad];
            derivedExt = ut.preferredFilenameExtension ?: @"";
            derivedMime = ut.preferredMIMEType ?: nil;
        }

        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:typeToLoad completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                    @try {
                        if (url && !error) {
                            // Build a suggested filename:
                            // 1) prefer provider.suggestedName if it already has an extension
                            // 2) otherwise use the original temp URL's lastPathComponent (often has the correct extension)
                            // 3) finally, append UTType-derived extension if still missing
                            NSString *suggested = provider.suggestedName ?: @"";
                            NSString *urlName = url.lastPathComponent ?: @"";
                            NSString *extFromSuggested = suggested.pathExtension;
                            NSString *extFromURL = urlName.pathExtension;

                            if (suggested.length == 0) {
                                suggested = urlName.length ? urlName : [NSUUID UUID].UUIDString;
                            }
                            if (extFromSuggested.length == 0 && extFromURL.length > 0) {
                                suggested = urlName;
                                extFromSuggested = extFromURL;
                            }
                            if (suggested.pathExtension.length == 0 && derivedExt.length > 0) {
                                suggested = [suggested stringByAppendingPathExtension:derivedExt];
                            }

                            NSString *destPath = [cacheDir stringByAppendingPathComponent:suggested];
                            NSURL *destURL = [NSURL fileURLWithPath:destPath];

                            NSInteger suffix = 1;
                            NSString *base = [suggested stringByDeletingPathExtension];
                            NSString *ext = [suggested pathExtension];
                            while ([fm fileExistsAtPath:destPath]) {
                                NSString *candidate = ext.length > 0 ? [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)suffix, ext] : [NSString stringWithFormat:@"%@ (%ld)", base, (long)suffix];
                                destPath = [cacheDir stringByAppendingPathComponent:candidate];
                                destURL = [NSURL fileURLWithPath:destPath];
                                suffix++;
                            }

                            NSError *copyErr = nil;
                            if (![fm copyItemAtURL:url toURL:destURL error:&copyErr]) {
                                NSData *data = [NSData dataWithContentsOfURL:url];
                                if (data) {
                                    [data writeToURL:destURL atomically:YES];
                                    copyErr = nil;
                                }
                            }
                            if (!copyErr && [fm fileExistsAtPath:destPath]) {
                                NSURL *finalURL = destURL;
                                NSError *conversionError = nil;
                                if ([typeToLoad isEqualToString:@"public.image"]) {
                                    finalURL = [self convertImageToJpegIfNeeded:destURL knownImage:YES error:&conversionError];
                                    if (conversionError) {
                                        @synchronized (collected) {
                                            if (!conversionFailure) {
                                                conversionFailure = conversionError;
                                            }
                                        }
                                    }
                                }

                                if (finalURL && !conversionError) {
                                    NSMutableDictionary *info = [[self buildFileInfoForURL:finalURL] mutableCopy];
                                    if (derivedMime.length > 0 && !info[@"mime"]) {
                                        info[@"mime"] = derivedMime;
                                    }
                                    @synchronized (collected) { if (info) [collected addObject:info]; }
                                }
                            }
                        }
                    } @catch (NSException *exception) {
                        // ignore individual item failure
                    } @finally {
                        dispatch_group_leave(group);
                    }
                }];

    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSError *fatalError = nil;
        @synchronized (collected) {
            fatalError = conversionFailure;
        }
        if (fatalError) {
            [self sendJpegConversionError:fatalError];
            return;
        }

        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:collected];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    });
}

@end
