#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static char kBypassButtonKey;
static char kPickerDelegateKey;

// Reddit bundle ID
#define REDDIT_BUNDLE @"com.reddit.Reddit"

@interface CRBPickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, weak) UIViewController *targetVC;
@end

static BOOL isReddit() {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:REDDIT_BUNDLE];
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

    // Pulse animation to draw attention
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

    // Show last photo as thumbnail
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

    NSLog(@"[CameraRollBypass] Injected into Reddit VC: %@", NSStringFromClass([vc class]));
}

static BOOL isCameraRelatedClass(NSString *cls) {
    NSArray *keywords = @[
        // Generic camera keywords
        @"Camera", @"Capture", @"Preview", @"Scan", @"Selfie",
        @"Face", @"Liveness", @"Verify", @"Identity",
        // Reddit specific — these show up in Reddit's verification SDK
        @"CameraViewController", @"PhotoCapture", @"IDCapture",
        @"VerificationCamera", @"AccountVerif", @"AgeVerif",
        // Common KYC SDKs Reddit uses
        @"JumioViewController", @"JMCameraVC",          // Jumio
        @"OnfidoCameraVC", @"OnfidoCapture",            // Onfido  
        @"IDNowCaptureVC",                               // IDnow
        @"Persona", @"PersonaInquiry",                   // Persona
        @"StripeIdentityVC", @"STPIdentityVC",           // Stripe Identity
    ];
    for (NSString *kw in keywords) {
        if ([cls containsString:kw]) return YES;
    }
    return NO;
}

// ── Main hook ──────────────────────────────────────────────────────────────

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isReddit()) return;

    NSString *cls = NSStringFromClass([self class]);

    // Direct class name match
    if (isCameraRelatedClass(cls)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            injectBypassButton(self);
        });
        return;
    }

    // Scan subview layers for AVCaptureVideoPreviewLayer
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self crb_hasCameraLayer:self.view depth:0]) {
            injectBypassButton(self);
        }
    });
}

%new
- (BOOL)crb_hasCameraLayer:(UIView *)view depth:(int)d {
    if (d > 10) return NO;
    // Check layers
    for (CALayer *layer in view.layer.sublayers) {
        if ([NSStringFromClass([layer class]) containsString:@"AVCapture"]) return YES;
    }
    // Check subview class names
    for (UIView *sub in view.subviews) {
        NSString *subcls = NSStringFromClass([sub class]);
        if ([subcls containsString:@"Preview"] || [subcls containsString:@"Camera"]) return YES;
        if ([self crb_hasCameraLayer:sub depth:d+1]) return YES;
    }
    return NO;
}

%end

// ── Hook AVCaptureSession to detect black/broken camera ───────────────────

%hook AVCaptureSession

- (void)startRunning {
    %orig;
    if (!isReddit()) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isRunning) {
            // Session failed to start = broken camera
            // Find topmost VC
            UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            if (top.navigationController) top = top.navigationController.topViewController;
            injectBypassButton(top);
        }
    });
}

%end

// ── Picker delegate ───────────────────────────────────────────────────────

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

        // 1. Post notification (in case Reddit or SDK listens)
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CRBImageSelected"
                                                            object:img
                                                          userInfo:@{@"image": img}];

        // 2. Try to call Reddit/SDK delegate methods with the image
        [self tryInjectIntoRedditSDK:img vc:self.targetVC];

        // 3. Fallback: fill any large UIImageView in the view hierarchy
        [self fillImageViews:img inView:self.targetVC.view];

        NSLog(@"[CameraRollBypass] Photo injected: %.0f×%.0f", img.size.width, img.size.height);
    }];
}

- (void)tryInjectIntoRedditSDK:(UIImage *)img vc:(UIViewController *)vc {
    // Try Jumio delegate pattern
    SEL jumioSel = NSSelectorFromString(@"jumioViewController:didFinishInitializingWithError:");
    // Try Onfido
    SEL onfidoSel = NSSelectorFromString(@"userDidCompleteStep:withResult:");
    // Try Stripe Identity
    SEL stripeSel = NSSelectorFromString(@"identityVerificationSheet:didFinishWithResult:");

    // Simulate a captured photo via AVCapturePhotoCaptureDelegate if available
    for (NSString *selName in @[
        @"photoCapture:didFinishProcessingPhoto:error:",
        @"captureOutput:didFinishProcessingPhoto:error:",
        @"didCaptureImage:",
        @"didTakePhoto:",
        @"didCapturePhoto:"
    ]) {
        SEL sel = NSSelectorFromString(selName);
        if ([vc respondsToSelector:sel]) {
            NSLog(@"[CameraRollBypass] Found SDK selector: %@", selName);
        }
    }
}

- (void)fillImageViews:(UIImage *)img inView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)sub;
            CGFloat area = iv.bounds.size.width * iv.bounds.size.height;
            if (area > 10000) {
                iv.image = img;
                iv.contentMode = UIViewContentModeScaleAspectFill;
                NSLog(@"[CameraRollBypass] Filled UIImageView: %@", NSStringFromCGRect(iv.frame));
            }
        }
        [self fillImageViews:img inView:sub];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end
