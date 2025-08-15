#import "PNFilePicker.h"

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
                    config.filter = [PHPickerFilter images];
                } else if ([mediaTypes.lowercaseString isEqualToString:@"videos"]) {
                    config.filter = [PHPickerFilter videos];
                } else {
                    config.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[[PHPickerFilter images], [PHPickerFilter videos]]];
                }
                config.selectionLimit = weakSelf.selectionLimit > 0 ? weakSelf.selectionLimit : (multiple ? 0 : 1);

                PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
                picker.delegate = weakSelf;
                picker.modalPresentationStyle = UIModalPresentationFormSheet;

                UIViewController *vc = weakSelf.viewController;
                while (vc.presentedViewController) { vc = vc.presentedViewController; }
                [vc presentViewController:picker animated:YES completion:nil];
            } else {
                // Fallback to document picker if PHPicker unavailable
                [weakSelf presentDocumentPickerAllowMultiple:multiple];
            }
        } else {
            [weakSelf presentDocumentPickerAllowMultiple:multiple];
        }
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
                // Assume UTI identifier passed directly
                [docTypes addObject:s];
            }
        }
        if (docTypes.count > 0) return docTypes;
    }
    return @[ @"public.data" ];
}

- (NSDictionary *)buildFileInfoForURL:(NSURL *)url
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (!url) return info;
    info[@"uri"] = url.absoluteString ?: @"";
    NSString *name = url.lastPathComponent ?: @"";
    if (name) info[@"name"] = name;

    // File attributes: size and dates
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

    // Mime type from extension
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
        // Fallback simple guesses
        if ([@[ @"jpg", @"jpeg" ] containsObject:ext]) info[@"mime"] = @"image/jpeg";
        else if ([ext isEqualToString:@"png"]) info[@"mime"] = @"image/png";
        else if ([ext isEqualToString:@"gif"]) info[@"mime"] = @"image/gif";
        else if ([ext isEqualToString:@"pdf"]) info[@"mime"] = @"application/pdf";
    }

    // Image dimensions
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

    for (NSURL *url in urls) {
        BOOL accessStarted = [url startAccessingSecurityScopedResource];
        @try {
            NSString *fileName = url.lastPathComponent ? url.lastPathComponent : [[NSUUID UUID] UUIDString];
            NSString *destPath = [cacheDir stringByAppendingPathComponent:fileName];
            NSURL *destURL = [NSURL fileURLWithPath:destPath];

            // Ensure unique filename
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
                NSDictionary *info = [self buildFileInfoForURL:destURL];
                if (info) [result addObject:info];
            }
        } @catch (NSException *exception) {
            // ignore individual file failure
        } @finally {
            if (accessStarted) {
                [url stopAccessingSecurityScopedResource];
            }
        }
    }

    // Enforce selection limit for document results if needed
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

// PHPicker delegate
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

        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:typeToLoad completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
            @try {
                if (url && !error) {
                    NSString *suggested = provider.suggestedName ?: url.lastPathComponent ?: [[NSUUID UUID] UUIDString];
                    NSString *destPath = [cacheDir stringByAppendingPathComponent:suggested];
                    NSURL *destURL = [NSURL fileURLWithPath:destPath];

                    // unique name
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
                        // Attempt data copy
                        NSData *data = [NSData dataWithContentsOfURL:url];
                        if (data) {
                            [data writeToURL:destURL atomically:YES];
                            copyErr = nil;
                        }
                    }
                    if (!copyErr && [fm fileExistsAtPath:destPath]) {
                        NSDictionary *info = [self buildFileInfoForURL:destURL];
                        @synchronized (collected) { if (info) [collected addObject:info]; }
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
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:collected];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        self.callbackId = nil;
    });
}

@end
