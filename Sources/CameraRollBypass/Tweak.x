#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static char kBypassButtonKey;
static char kPickerDelegateKey;

#define REDDIT_BUNDLE @"com.reddit.Reddit"

@interface CRBPickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, weak) UIViewController *targetVC;
@end

static BOOL isReddit() {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:REDDIT_BUNDLE];
}

static UIWindow *getKeyWindow() {
    UIWindow *keyWindow = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        }
    }
    return keyWindow;
}

static BOOL hasCameraLayer(UIView *view, int depth) {
    if (depth > 10) return NO;
    for (CALayer *layer in view.layer.sublayers) {
        if ([NSStringFromClass([layer class]) containsString:@"AVCapture"]) return YES;
    }
    for (UIView *sub in view.subviews) {
        NSString *subcls = NSStringFromClass([sub class]);
        if ([subcls containsString:@"Preview"] || [subcls containsString:@"Camera"]) return YES;
        if (hasCameraLayer(sub, depth + 1)) return YES;
    }
    return NO;
}

static void injectBypassButton(UIViewController *vc) {
    if (!vc || !vc.view) return;
    UIView *view = vc.view;
    if (objc_getAssociatedObject(view, &kBypassButtonKey)) return;

    CGFloat size = 70;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(16, view.bounds.size.height - size - 24, size, size);
    btn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    btn.layer.cornerRadius = 14;
    btn.layer.borderWidth = 3;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
    btn.clipsToBounds = YES;
    btn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @1.0;
    pulse.toValue = @0.5;
    pulse.duration = 0.9;
    pulse.autoreverses = YES;
    pulse.repeatCount = 4;
    [btn.layer addAnimation:pulse forKey:@"pulse"];

    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, size, 36)];
    icon.text = @"🖼️";
    icon.font = [UIFont systemFontOfSize:28];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.userInteractionEnabled = NO;
    [btn addSubview:icon];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 46, size, 14)];
    hint.text = @"GALLERY";
    hint.font = [UIFont boldSystemFontOfSize:8];
    hint.textColor = [UIColor whiteColor];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.userInteractionEnabled = NO;
    [btn addSubview:hint];

    PHFetchOptions *opts = [PHFetchOptions new];
    opts.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    opts.fetchLimit = 1;
    PHFetchResult *res = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:opts];
    if (res.count > 0) {
        [[PHImageManager defaultManager] requestImageForAsset:res.firstObject
                                                   targetSize:CGSizeMake(140, 140)
                                                  contentMode:PHImageContentModeAspectFill
                                                      options:nil
                                                resultHandler:^(UIImage *img, NSDictionary *info) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (img) {
                    [btn setImage:img forState:UIControlStateNormal];
                    btn.imageView.contentMode = UIViewContentModeScaleAspectFill;
                    icon.hidden = YES;
                    hint.hidden = YES;
                }
            });
        }];
    }

    CRBPickerDelegate *delegate = [CRBPickerDelegate new];
    delegate.targetVC = vc;
    objc_setAssociatedObject(view, &kPickerDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btn addTarget:delegate action:@selector(openGallery:) forControlEvents:UIControlEventTouchUpInside];

    [view addSubview:btn];
    [view bringSubviewToFront:btn];
    objc_setAssociatedObject(view, &kBypassButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"[CameraRollBypass] Injected into: %@", NSStringFromClass([vc class]));
}

static BOOL isCameraRelatedClass(NSString *cls) {
    NSArray *keywords = @[
        @"Camera", @"Capture", @"Preview", @"Scan", @"Selfie",
        @"Face", @"Liveness", @"Verify", @"Identity",
        @"JumioViewController", @"JMCameraVC",
        @"OnfidoCameraVC", @"OnfidoCapture",
        @"Persona", @"PersonaInquiry",
        @"StripeIdentityVC", @"STPIdentityVC",
    ];
    for (NSString *kw in keywords) {
        if ([cls containsString:kw]) return YES;
    }
    return NO;
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isReddit()) return;

    NSString *cls = NSStringFromClass([self class]);
    UIViewController *selfVC = self;

    if (isCameraRelatedClass(cls)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            injectBypassButton(selfVC);
        });
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (hasCameraLayer(selfVC.view, 0)) {
            injectBypassButton(selfVC);
        }
    });
}

%end

%hook AVCaptureSession

- (void)startRunning {
    %orig;
    if (!isReddit()) return;

    AVCaptureSession *session = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!session.isRunning) {
            UIWindow *keyWindow = getKeyWindow();
            UIViewController *top = keyWindow.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            if (top.navigationController) top = top.navigationController.topViewController;
            injectBypassButton(top);
        }
    });
}

%end

@implementation CRBPickerDelegate

- (void)openGallery:(id)sender {
    UIViewController *vc = self.targetVC;
    if (!vc) return;

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"Photos Access Needed"
                    message:@"Go to Settings → Reddit → Photos and allow access."
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                    style:UIAlertActionStyleDefault handler:nil]];
                [vc presentViewController:alert animated:YES completion:nil];
                return;
            }
            UIImagePickerController *picker = [UIImagePickerController new];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.mediaTypes = @[@"public.image"];
            picker.allowsEditing = NO;
            picker.delegate = self;
            [vc presentViewController:picker animated:YES completion:nil];
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {

    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!img || !self.targetVC) return;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CRBImageSelected"
                                                            object:img
                                                          userInfo:@{@"image": img}];
        [self fillImageViews:img inView:self.targetVC.view];
        NSLog(@"[CameraRollBypass] Photo injected: %.0f×%.0f", img.size.width, img.size.height);
    }];
}

- (void)fillImageViews:(UIImage *)img inView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)sub;
            if (iv.bounds.size.width * iv.bounds.size.height > 8000) {
                iv.image = img;
                iv.contentMode = UIViewContentModeScaleAspectFill;
            }
        }
        [self fillImageViews:img inView:sub];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end
