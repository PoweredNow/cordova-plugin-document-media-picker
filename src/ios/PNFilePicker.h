#import <Cordova/CDVPlugin.h>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface PNFilePicker : CDVPlugin <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>

@property (nonatomic, strong) NSString *callbackId;
@property (nonatomic, strong) NSDictionary *options;
@property (nonatomic, assign) NSInteger selectionLimit;

- (void)showPicker:(CDVInvokedUrlCommand*)command;

@end
