// ╔══════════════════════════════════════════════════╗
// ║  FakeCam — AhmadDev © 2026                      ║
// ║  Camera Interception dylib for Minichat         ║
// ╚══════════════════════════════════════════════════╝

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

// ═══════════════════════════════════════════════
// AhmadDev Theme Colors
// ═══════════════════════════════════════════════
static UIColor *_ad_bg(void)    { return [UIColor colorWithRed:28/255.f green:43/255.f blue:59/255.f alpha:1.0]; }
static UIColor *_ad_grn(void)   { return [UIColor colorWithRed:46/255.f green:204/255.f blue:112/255.f alpha:1.0]; }
static UIColor *_ad_grnA(float a) { return [UIColor colorWithRed:46/255.f green:204/255.f blue:112/255.f alpha:a]; }
static UIColor *_ad_wht(float a) { return [UIColor colorWithWhite:1.0 alpha:a]; }

// ═══════════════════════════════════════════════
// AhmadDev Global State
// ═══════════════════════════════════════════════
static BOOL _ad_intercepting = NO;
static BOOL _ad_active = NO;
static NSString *_ad_mediaType = @"none";
static UIImage *_ad_sourceImage = nil;        // صورة فقط (ليس thumbnail فيديو)
static NSURL *_ad_sourceVideoURL = nil;
static UIImage *_ad_videoThumbnail = nil;      // صورة مصغرة للفيديو (للمعاينة فقط)
static int _ad_targetW = 640;
static int _ad_targetH = 480;
static int _ad_targetFPS = 30;

// UI
static UIWindow *_ad_panelWin = nil;
static UIButton *_ad_fabBtn = nil;
static UIView *_ad_panelView = nil;
static UIImageView *_ad_previewImg = nil;
static UIView *_ad_previewBox = nil;
static AVPlayer *_ad_previewPlayer = nil;
static AVPlayerLayer *_ad_previewPlayerLayer = nil;
static UILabel *_ad_statusLabel = nil;
static UIView *_ad_statusDot = nil;
static UIView *_ad_toggleKnob = nil;
static UIView *_ad_toggleBg = nil;
static UIButton *_ad_swapBtn = nil;
static UILabel *_ad_typeBadge = nil;
static BOOL _ad_panelVisible = NO;
static BOOL _ad_toggleOn = NO;

// Frames
static dispatch_source_t _ad_frameTimer = nil;
static AVAssetReader *_ad_videoReader = nil;
static AVAssetReaderTrackOutput *_ad_videoOutput = nil;
static AVAsset *_ad_videoAsset = nil;
static CVPixelBufferRef _ad_imagePixelBuf = NULL;
static __weak id _ad_currentCapturer = nil;

// ═══════════════════════════════════════════════
// AhmadDev Hooks — New Approach
// DON'T block startCapture — let camera run normally
// Intercept captureOutput:didOutputSampleBuffer:fromConnection: instead
// ═══════════════════════════════════════════════

static IMP _ad_orig_captureOutput = NULL;
static IMP _ad_orig_switchCamera = NULL;
static IMP _ad_orig_startWatchingFace = NULL;
static IMP _ad_orig_startWatchingFaceH = NULL;
static IMP _ad_orig_stopLocalStream = NULL;
static IMP _ad_orig_setAYTHidden = NULL;

// ═══════════════════════════════════════════════
// AhmadDev Status
// ═══════════════════════════════════════════════
static void _ad_updateStatus(NSString *text, UIColor *color, BOOL active) {
    _ad_active = active;
    dispatch_async(dispatch_get_main_queue(), ^{
        _ad_statusLabel.text = text;
        _ad_statusLabel.textColor = color;
        _ad_statusDot.backgroundColor = active ? _ad_grn() : _ad_wht(0.2);
        [_ad_fabBtn setTitleColor:active ? _ad_grn() : _ad_wht(0.2) forState:UIControlStateNormal];
        if (active) {
            [_ad_swapBtn setTitle:@"🖼️ بث وهمي" forState:UIControlStateNormal];
            _ad_swapBtn.backgroundColor = _ad_grnA(0.25);
            _ad_swapBtn.layer.borderColor = _ad_grnA(0.5).CGColor;
        } else {
            [_ad_swapBtn setTitle:@"📷 كاميرا حقيقية" forState:UIControlStateNormal];
            _ad_swapBtn.backgroundColor = _ad_grnA(0.12);
            _ad_swapBtn.layer.borderColor = _ad_grnA(0.3).CGColor;
        }
    });
}

// ═══════════════════════════════════════════════
// AhmadDev Frame Generator
// ═══════════════════════════════════════════════
static CVPixelBufferRef _ad_imageToPixelBuf(UIImage *image, int w, int h) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h)];
    UIImage *resized = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, w, h)];
    }];
    CGImageRef cgImg = resized.CGImage;
    if (!cgImg) return NULL;
    
    CVPixelBufferRef pxBuf = NULL;
    NSDictionary *attrs = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    if (CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                             (__bridge CFDictionaryRef)attrs, &pxBuf) != kCVReturnSuccess)
        return NULL;
    
    CVPixelBufferLockBaseAddress(pxBuf, 0);
    CGContextRef ctx = CGBitmapContextCreate(
        CVPixelBufferGetBaseAddress(pxBuf), w, h, 8,
        CVPixelBufferGetBytesPerRow(pxBuf), CGColorSpaceCreateDeviceRGB(),
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (!ctx) { CVPixelBufferUnlockBaseAddress(pxBuf, 0); CFRelease(pxBuf); return NULL; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgImg);
    CGContextRelease(ctx);
    CVPixelBufferUnlockBaseAddress(pxBuf, 0);
    return pxBuf;
}

static CMSampleBufferRef _ad_makeSampleBuf(CVPixelBufferRef pxBuf, int fps) {
    CMFormatDescriptionRef fmt = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pxBuf, &fmt) != noErr)
        return NULL;
    CMTime dur = CMTimeMake(1, fps);
    CMTime pts = CMTimeMake((int64_t)([[NSDate date] timeIntervalSince1970] * fps), fps);
    CMSampleTimingInfo timing = {dur, pts, kCMTimeInvalid};
    CMSampleBufferRef sBuf = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pxBuf, true, NULL, NULL,
                                        fmt, &timing, &sBuf);
    CFRelease(fmt);
    return sBuf;
}


static void _ad_stopFrames(void);



static void _ad_stopFrames(void) {
    if (_ad_frameTimer) { dispatch_source_cancel(_ad_frameTimer); _ad_frameTimer = nil; }
    [_ad_videoReader cancelReading];
    _ad_videoReader = nil; _ad_videoOutput = nil; _ad_videoAsset = nil;
    if (_ad_imagePixelBuf) { CVBufferRelease(_ad_imagePixelBuf); _ad_imagePixelBuf = NULL; }
    _ad_currentCapturer = nil;
    // إيقاف معاينة الفيديو
    [_ad_previewPlayer pause]; _ad_previewPlayer = nil;
    [_ad_previewPlayerLayer removeFromSuperlayer]; _ad_previewPlayerLayer = nil;
}
// ═══════════════════════════════════════════════
// AhmadDev Hooks — New Approach
// Let camera run, intercept frames at captureOutput
// ═══════════════════════════════════════════════

// Hook 1: captureOutput:didOutputSampleBuffer:fromConnection:
// This is THE key hook — called for every frame from camera
// When intercepting: send our fake frame AFTER the real one
static void _ad_hooked_captureOutput(id self, SEL _cmd, id output, CMSampleBufferRef sampleBuffer, id connection) {
    if (!_ad_intercepting || (!_ad_sourceImage && !_ad_sourceVideoURL)) {
        // Not intercepting — pass through real frame
        if (_ad_orig_captureOutput)
            ((void(*)(id,SEL,id,CMSampleBufferRef,id))_ad_orig_captureOutput)(self, _cmd, output, sampleBuffer, connection);
        return;
    }
    
    // Mark as active (we're in a call)
    if (!_ad_active) {
        _ad_updateStatus(_ad_sourceVideoURL ? @"البث يعمل — فيديو" : @"البث يعمل — صورة", _ad_grnA(0.8), YES);
    }
    
    // Interception active — prepare fake frame
    // فيديو = أولوية (إطارات حقيقية من الفيديو)
    // صورة = خيار ثاني
    CMSampleBufferRef fakeBuf = NULL;
    
    if (_ad_sourceVideoURL) {
        // فيديو — قراءة الإطار التالي
        if (_ad_videoOutput) {
            fakeBuf = [_ad_videoOutput copyNextSampleBuffer];
            if (!fakeBuf) {
                // Loop video
                [_ad_videoReader cancelReading];
                _ad_videoReader = [[AVAssetReader alloc] initWithAsset:_ad_videoAsset error:nil];
                AVAssetTrack *track = [[_ad_videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
                if (track) {
                    NSDictionary *settings = @{
                        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                        (id)kCVPixelBufferWidthKey: @(_ad_targetW),
                        (id)kCVPixelBufferHeightKey: @(_ad_targetH)
                    };
                    _ad_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
                    _ad_videoOutput.supportsRandomAccess = YES;
                    [_ad_videoReader addOutput:_ad_videoOutput];
                    [_ad_videoReader startReading];
                    fakeBuf = [_ad_videoOutput copyNextSampleBuffer];
                }
            }
        }
    } else if (_ad_sourceImage && _ad_imagePixelBuf) {
        if (_ad_videoOutput) {
            fakeBuf = [_ad_videoOutput copyNextSampleBuffer];
            if (!fakeBuf) {
                // Loop video
                [_ad_videoReader cancelReading];
                _ad_videoReader = [[AVAssetReader alloc] initWithAsset:_ad_videoAsset error:nil];
                AVAssetTrack *track = [[_ad_videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
                if (track) {
                    NSDictionary *settings = @{
                        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                        (id)kCVPixelBufferWidthKey: @(_ad_targetW),
                        (id)kCVPixelBufferHeightKey: @(_ad_targetH)
                    };
                    _ad_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
                    _ad_videoOutput.supportsRandomAccess = YES;
                    [_ad_videoReader addOutput:_ad_videoOutput];
                    [_ad_videoReader startReading];
                    fakeBuf = [_ad_videoOutput copyNextSampleBuffer];
                }
            }
        }
    }
    
    if (fakeBuf) {
        // Send FAKE frame through the pipeline — NO real frames escape
        if (_ad_orig_captureOutput)
            ((void(*)(id,SEL,id,CMSampleBufferRef,id))_ad_orig_captureOutput)(self, _cmd, output, fakeBuf, connection);
        CFRelease(fakeBuf);
    } else if (_ad_sourceImage && _ad_imagePixelBuf) {
        // Fallback لصورة ثابتة إذا الفيديو فشل
        CMSampleBufferRef imgBuf = _ad_makeSampleBuf(_ad_imagePixelBuf, _ad_targetFPS);
        if (imgBuf) {
            if (_ad_orig_captureOutput)
                ((void(*)(id,SEL,id,CMSampleBufferRef,id))_ad_orig_captureOutput)(self, _cmd, output, imgBuf, connection);
            CFRelease(imgBuf);
        } else {
            // Last resort — drop the frame entirely (black > real)
        }
    } else {
        // No fake frame available — drop real frame (show nothing is better than real camera)
    }
}

// Hook 2: switchCamera — block while active
static void _ad_hooked_switchCamera(id self, SEL _cmd) {
    if (_ad_active) return;
    if (_ad_orig_switchCamera) ((void(*)(id,SEL))_ad_orig_switchCamera)(self, _cmd);
}

// Hook 3: startWatchingFace — disable both variants
static void _ad_hooked_startWatchingFace(id self, SEL _cmd) { return; }
static void _ad_hooked_startWatchingFaceH(id self, SEL _cmd, id handler) { return; }

// Hook 3b: VideoChatButtonsView.setAreYouThereViewHidden:model: — هذا المكان اللي يعرض التحذير
// نفعّل الزر بعد 1 ثانية عبر subviews
static void _ad_hooked_setAYTHidden(id self, SEL _cmd, bool hidden, id model) {
    // نستدعي الأصلي عادي
    if (_ad_orig_setAYTHidden)
        ((void(*)(id,SEL,bool,id))_ad_orig_setAYTHidden)(self, _cmd, hidden, model);
    
    // hidden = false يعني يعرض التحذير
    if (!hidden) {
        NSLog(@"[AhmadDev FakeCam] 🎯 AreYouThereView SHOWN (hidden=%d)", hidden);
        
        // بعد 1 ثانية: فعّل الزر
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
            Class vcbClass = objc_getClass("_TtC8Minichat15VideoChatButton");
            Class aytClass = objc_getClass("_TtC8Minichat23MinichatAreYouThereView");
            if (!vcbClass || !aytClass) return;
            
            // نلاقي AreYouThereView
            NSMutableArray *stack = [[NSMutableArray alloc] initWithArray:[(UIView *)self subviews]];
            UIView *aytView = nil;
            while (stack.count > 0) {
                UIView *v = [stack lastObject]; [stack removeLastObject];
                if ([v isKindOfClass:aytClass]) { aytView = v; break; }
                [stack addObjectsFromArray:v.subviews];
            }
            
            if (!aytView) {
                NSLog(@"[AhmadDev FakeCam] ❌ AreYouThereView not found in subviews");
                return;
            }
            
            NSLog(@"[AhmadDev FakeCam] ✅ Found AreYouThereView");
            
            // داخل AreYouThereView: نبحث عن VideoChatButton
            [stack removeAllObjects];
            [stack addObjectsFromArray:aytView.subviews];
            while (stack.count > 0) {
                UIView *v = [stack lastObject]; [stack removeLastObject];
                if ([v isKindOfClass:vcbClass]) {
                    [v setUserInteractionEnabled:YES];
                    NSLog(@"[AhmadDev FakeCam] ✅ VideoChatButton FOUND + enabled");
                    // غيّر نص الـ UILabel
                    for (UIView *sub in v.subviews) {
                        if ([sub isKindOfClass:[UILabel class]]) {
                            [(UILabel *)sub setText:@"OK"];
                            NSLog(@"[AhmadDev FakeCam] ✅ Label → OK");
                        }
                    }
                    return;
                }
                [stack addObjectsFromArray:v.subviews];
            }
            NSLog(@"[AhmadDev FakeCam] ❌ VideoChatButton not found inside AreYouThereView");
        });
    }
}

// Hook 4: stopLocalStream — cleanup
static void _ad_hooked_stopLocalStream(id self, SEL _cmd) {
    _ad_stopFrames();
    _ad_updateStatus(@"في الانتظار...", _ad_wht(0.4), NO);
    if (_ad_orig_stopLocalStream) ((void(*)(id,SEL))_ad_orig_stopLocalStream)(self, _cmd);
}
// ═══════════════════════════════════════════════
// AhmadDev Hook Installer
// ═══════════════════════════════════════════════
static void _ad_hookMethod(Class cls, SEL sel, IMP newIMP, IMP *origIMP) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *origIMP = method_getImplementation(m);
    method_setImplementation(m, newIMP);
}

static void _ad_installHooks(void);

static void _ad_installHooks(void) {
    Class rtcClass = objc_getClass("RTCCameraVideoCapturer");
    if (!rtcClass) {
        NSLog(@"[AhmadDev FakeCam] WebRTC not loaded, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                        dispatch_get_main_queue(), ^{ _ad_installHooks(); });
        return;
    }
    
    // NEW: Hook captureOutput to intercept frames (not startCapture)
    _ad_hookMethod(rtcClass, @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                    (IMP)_ad_hooked_captureOutput, &_ad_orig_captureOutput);
    
    Class vciClass = objc_getClass("_TtC8Minichat19VideoChatInteractor");
    if (vciClass) {
        _ad_hookMethod(vciClass, @selector(switchCamera),
                        (IMP)_ad_hooked_switchCamera, &_ad_orig_switchCamera);
        _ad_hookMethod(vciClass, NSSelectorFromString(@"startWatchingFace"),
                        (IMP)_ad_hooked_startWatchingFace, &_ad_orig_startWatchingFace);
        _ad_hookMethod(vciClass, NSSelectorFromString(@"startWatchingFace:withHandler:"),
                        (IMP)_ad_hooked_startWatchingFaceH, &_ad_orig_startWatchingFaceH);
        _ad_hookMethod(vciClass, NSSelectorFromString(@"stopLocalStream"),
                        (IMP)_ad_hooked_stopLocalStream, &_ad_orig_stopLocalStream);
    }
    
    // Hook VideoChatButtonsView.setAreYouThereViewHidden:model: — المكان الفعلي لعرض التحذير
    Class buttonsViewCls = objc_getClass("_TtC8Minichat20VideoChatButtonsView");
    if (buttonsViewCls) {
        _ad_hookMethod(buttonsViewCls, NSSelectorFromString(@"setAreYouThereViewHidden:model:"),
                        (IMP)_ad_hooked_setAYTHidden, &_ad_orig_setAYTHidden);
        NSLog(@"[AhmadDev FakeCam] ✅ setAreYouThereViewHidden:model: hooked");
    }
    
    NSLog(@"[AhmadDev FakeCam] ✅ All hooks installed (captureOutput approach)");
}

// ═══════════════════════════════════════════════
// AhmadDev Picker Delegate
// ═══════════════════════════════════════════════
@interface AhmadDevPickerController : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end
@implementation AhmadDevPickerController
- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSURL *url = info[UIImagePickerControllerMediaURL];
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    // إيقاف أي بث سابق
    _ad_stopFrames();
    _ad_sourceImage = nil;
    _ad_videoThumbnail = nil;
    _ad_sourceVideoURL = nil;
    
    if (url) {
        _ad_sourceVideoURL = url;
        _ad_mediaType = @"video";
        // حفظ الصورة المصغرة للمعاينة فقط (لا تستخدم في الاعتراض)
        AVAsset *a = [AVAsset assetWithURL:url];
        AVAssetImageGenerator *g = [[AVAssetImageGenerator alloc] initWithAsset:a];
        g.appliesPreferredTrackTransform = YES;
        CGImageRef cg = [g copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];
        if (cg) { _ad_videoThumbnail = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        
        // تحضير قارئ الفيديو فوراً
        _ad_videoAsset = [AVAsset assetWithURL:url];
        AVAssetTrack *track = [[_ad_videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        if (track) {
            NSDictionary *settings = @{
                (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                (id)kCVPixelBufferWidthKey: @(_ad_targetW),
                (id)kCVPixelBufferHeightKey: @(_ad_targetH)
            };
            _ad_videoReader = [[AVAssetReader alloc] initWithAsset:_ad_videoAsset error:nil];
            _ad_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
            _ad_videoOutput.supportsRandomAccess = YES;
            [_ad_videoReader addOutput:_ad_videoOutput];
            [_ad_videoReader startReading];
            NSLog(@"[AhmadDev FakeCam] Video reader ready: %lld frames", (long long)(CMTimeGetSeconds(_ad_videoAsset.duration) * 30));
        }
    } else if (img) {
        _ad_sourceImage = img;
        _ad_sourceVideoURL = nil;
        _ad_mediaType = @"image";
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // تحديث المعاينة
        UIImage *previewImg = _ad_sourceVideoURL ? _ad_videoThumbnail : _ad_sourceImage;
        _ad_previewImg.image = previewImg;
        _ad_typeBadge.hidden = NO;
        _ad_typeBadge.text = [_ad_mediaType isEqualToString:@"video"] ? @"🎬 فيديو" : @"🖼️ صورة";
        // Remove placeholder emoji
        UIView *prevBox = _ad_previewImg.superview;
        if (prevBox) {
            UIView *placeholder = [prevBox viewWithTag:999];
            [placeholder removeFromSuperview];
        }
        // إذا فيديو — شغّل المعاينة المتحركة
        if (_ad_sourceVideoURL) {
            [_ad_previewPlayer pause];
            [_ad_previewPlayerLayer removeFromSuperlayer];
            AVURLAsset *pa = [AVURLAsset URLAssetWithURL:_ad_sourceVideoURL options:nil];
            AVPlayerItem *pi = [AVPlayerItem playerItemWithAsset:pa];
            _ad_previewPlayer = [AVPlayer playerWithPlayerItem:pi];
            _ad_previewPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            // تأكد من وجود prevBox كبير للفيديو
            if (_ad_previewBox) {
                _ad_previewPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_ad_previewPlayer];
                _ad_previewPlayerLayer.frame = _ad_previewBox.bounds;
                _ad_previewPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                [_ad_previewBox.layer addSublayer:_ad_previewPlayerLayer];
                _ad_previewImg.hidden = YES;
                [_ad_previewPlayer play];
                // Loop
                [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:pi queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                    [_ad_previewPlayer seekToTime:kCMTimeZero];
                    [_ad_previewPlayer play];
                }];
                NSLog(@"[AhmadDev FakeCam] Video preview playing");
            }
        } else {
            // صورة — أوقف أي فيديو سابق
            [_ad_previewPlayer pause]; _ad_previewPlayer = nil;
            [_ad_previewPlayerLayer removeFromSuperlayer]; _ad_previewPlayerLayer = nil;
            _ad_previewImg.hidden = NO;
        }
    });
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end
static AhmadDevPickerController *_ad_pickerDel = nil;

// ═══════════════════════════════════════════════
// AhmadDev Panel UI
// ═══════════════════════════════════════════════

// ════════════════════════════════════════════════
// AhmadDev Pass-Through Window
// Only captures touches on FAB/Panel, passes everything else
// ════════════════════════════════════════════════
@interface AhmadDevOverlayWindow : UIWindow
@end

// Forward declarations
static void _ad_showPanel(void);
static void _ad_hidePanel(void);

@implementation AhmadDevOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Only capture if touch is on FAB or panel, otherwise pass through
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ════════════════════════════════════════════════
// AhmadDev Drag Gesture for FAB
// ════════════════════════════════════════════════
@interface AhmadDevFabTarget : NSObject
- (void)onFabTap;
- (void)onMinimize;
- (void)onImport;
- (void)onToggleTap:(UITapGestureRecognizer *)g;
- (void)onSwapTap;
- (void)onFabDrag:(UIPanGestureRecognizer *)pan;
- (void)onPanelDrag:(UIPanGestureRecognizer *)pan;
@end
@implementation AhmadDevFabTarget {
    CGPoint _dragStart;
    BOOL _didDrag;
}
- (void)onFabTap { 
    if (_didDrag) { _didDrag = NO; return; }
    if (_ad_panelVisible) _ad_hidePanel(); else _ad_showPanel(); 
}
- (void)onMinimize { _ad_hidePanel(); }
- (void)onImport {
    // Make our window key temporarily so picker shows
    [_ad_panelWin makeKeyAndVisible];
    _ad_pickerDel = [[AhmadDevPickerController alloc] init];
    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    p.mediaTypes = @[@"public.image", @"public.movie"];
    p.delegate = _ad_pickerDel;
    [_ad_panelWin.rootViewController presentViewController:p animated:YES completion:NULL];
}
- (void)onToggleTap:(UITapGestureRecognizer *)g {
    _ad_toggleOn = !_ad_toggleOn;
    _ad_intercepting = _ad_toggleOn;
    [UIView animateWithDuration:0.3 animations:^{
        _ad_toggleBg.backgroundColor = _ad_toggleOn ? _ad_grnA(0.8) : _ad_wht(0.08);
        _ad_toggleKnob.frame = CGRectMake(_ad_toggleOn ? 22 : 2, 2, 20, 20);
    }];
    // No media loaded? Open import automatically
    if (_ad_toggleOn && !_ad_sourceImage && !_ad_sourceVideoURL) {
        [self onImport];
    }
    // Update status immediately
    if (_ad_toggleOn) {
        if (_ad_sourceImage || _ad_sourceVideoURL) {
            _ad_updateStatus(@"جاهز — في انتظار مكالمة...", _ad_grnA(0.6), NO);
            // Prepare fake frames for IMAGE mode
            if (_ad_sourceImage && !_ad_imagePixelBuf) {
                _ad_imagePixelBuf = _ad_imageToPixelBuf(_ad_sourceImage, _ad_targetW, _ad_targetH);
            }
            // Video reader should already be prepared in picker delegate
        }
    } else {
        _ad_stopFrames();
        _ad_updateStatus(@"في الانتظار...", _ad_wht(0.4), NO);
    }
}
- (void)onSwapTap {
    if (_ad_active) {
        // Stop fake frames and restore real camera
        _ad_stopFrames();
        _ad_updateStatus(@"في الانتظار...", _ad_wht(0.4), NO);
    }
}
- (void)onFabDrag:(UIPanGestureRecognizer *)pan {
    if (!_ad_fabBtn) return;
    CGPoint translation = [pan translationInView:_ad_fabBtn.superview];
    
    if (pan.state == UIGestureRecognizerStateBegan) {
        _dragStart = _ad_fabBtn.center;
        _didDrag = NO;
    }
    
    CGFloat dist = hypot(translation.x, translation.y);
    if (dist > 5) _didDrag = YES;
    if (!_didDrag) return;
    
    CGPoint newCenter = CGPointMake(_ad_fabBtn.center.x + translation.x, _ad_fabBtn.center.y + translation.y);
    CGRect bounds = _ad_fabBtn.superview.bounds;
    CGFloat hw = _ad_fabBtn.bounds.size.width / 2;
    CGFloat hh = _ad_fabBtn.bounds.size.height / 2;
    newCenter.x = MAX(hw, MIN(bounds.size.width - hw, newCenter.x));
    newCenter.y = MAX(hh, MIN(bounds.size.height - hh, newCenter.y));
    _ad_fabBtn.center = newCenter;
    [pan setTranslation:CGPointZero inView:_ad_fabBtn.superview];
    
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGPoint center = _ad_fabBtn.center;
        CGFloat midX = bounds.size.width / 2;
        CGFloat targetX = (center.x < midX) ? hw + 8 : bounds.size.width - hw - 8;
        [UIView animateWithDuration:0.25 animations:^{
            _ad_fabBtn.center = CGPointMake(targetX, center.y);
        }];
    }
}
- (void)onPanelDrag:(UIPanGestureRecognizer *)pan {
    if (!_ad_panelView) return;
    CGPoint translation = [pan translationInView:_ad_panelView.superview];
    _ad_panelView.center = CGPointMake(_ad_panelView.center.x + translation.x, _ad_panelView.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:_ad_panelView.superview];
}
@end
static AhmadDevFabTarget *_ad_targets = nil;

static void _ad_createFab(void) {
    if (_ad_fabBtn) return;
    
    _ad_targets = [[AhmadDevFabTarget alloc] init];
    
    // AhmadDevOverlayWindow — pass-through touches outside controls
    AhmadDevOverlayWindow *win = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            win = [[AhmadDevOverlayWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
            break;
        }
    }
    if (!win) win = [[AhmadDevOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.frame = [UIScreen mainScreen].bounds;
    win.windowLevel = UIWindowLevelAlert + 500;
    win.backgroundColor = [UIColor clearColor];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    win.rootViewController = vc;
    win.hidden = NO;
    // Do NOT makeKey — keep app's key window intact
    _ad_panelWin = win;
    
    // FAB button
    _ad_fabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _ad_fabBtn.frame = CGRectMake(16, 60, 48, 48);
    _ad_fabBtn.backgroundColor = _ad_bg();
    _ad_fabBtn.layer.cornerRadius = 24;
    _ad_fabBtn.layer.borderWidth = 2;
    _ad_fabBtn.layer.borderColor = _ad_grnA(0.6).CGColor;
    [_ad_fabBtn setTitle:@"●" forState:UIControlStateNormal];
    [_ad_fabBtn setTitleColor:_ad_wht(0.2) forState:UIControlStateNormal];
    _ad_fabBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    _ad_fabBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    _ad_fabBtn.layer.shadowOpacity = 0.3;
    _ad_fabBtn.layer.shadowOffset = CGSizeMake(0, 2);
    _ad_fabBtn.layer.shadowRadius = 4;
    // Drag gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:_ad_targets action:@selector(onFabDrag:)];
    [_ad_fabBtn addGestureRecognizer:pan];
    
    [_ad_fabBtn addTarget:_ad_targets action:@selector(onFabTap) forControlEvents:UIControlEventTouchUpInside];
    
    [vc.view addSubview:_ad_fabBtn];
    
    NSLog(@"[AhmadDev FakeCam] ✅ FAB shown");
}

static void _ad_showPanel(void) {
    if (_ad_panelView) return;
    _ad_panelVisible = YES;
    // Position panel near FAB
    CGFloat pw = 300, ph = 280;
    CGFloat fabX = _ad_fabBtn.frame.origin.x;
    CGFloat fabY = _ad_fabBtn.frame.origin.y + _ad_fabBtn.frame.size.height + 8;
    // Keep within screen
    CGFloat maxX = [UIScreen mainScreen].bounds.size.width - pw - 8;
    CGFloat px = MAX(8, MIN(maxX, fabX - 120));
    CGFloat py = MAX(8, MIN([UIScreen mainScreen].bounds.size.height - ph - 8, fabY));
    
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    panel.backgroundColor = _ad_bg();
    panel.layer.cornerRadius = 20;
    panel.layer.borderWidth = 2;
    panel.layer.borderColor = _ad_grnA(0.6).CGColor;
    
    // ... same panel code but use _ad_panelWin.rootViewController.view
    
    // Top bar drag area (whole top section)
    UIView *topBarBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 38)];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:_ad_targets action:@selector(onPanelDrag:)];
    [topBarBg addGestureRecognizer:panelPan];
    [panel addSubview:topBarBg];
    
    // Logo lines
    UIView *l1 = [[UIView alloc] initWithFrame:CGRectMake(14, 10, 11, 3.5)];
    l1.backgroundColor = _ad_grn(); l1.layer.cornerRadius = 2;
    l1.transform = CGAffineTransformMakeRotation(-0.35);
    [panel addSubview:l1];
    UIView *l2 = [[UIView alloc] initWithFrame:CGRectMake(14, 16, 14, 3.5)];
    l2.backgroundColor = [UIColor whiteColor]; l2.layer.cornerRadius = 2;
    [panel addSubview:l2];
    UIView *l3 = [[UIView alloc] initWithFrame:CGRectMake(14, 22, 11, 3.5)];
    l3.backgroundColor = _ad_grn(); l3.layer.cornerRadius = 2;
    l3.transform = CGAffineTransformMakeRotation(0.35);
    [panel addSubview:l3];
    
    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(32, 10, 20, 22)];
    logo.text = @"AD"; logo.font = [UIFont boldSystemFontOfSize:11]; logo.textColor = [UIColor whiteColor];
    [panel addSubview:logo];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(54, 10, 150, 22)];
    title.text = @"FakeCam"; title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = _ad_wht(0.85);
    [panel addSubview:title];
    
    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame = CGRectMake(pw - 36, 8, 22, 22);
    minBtn.backgroundColor = _ad_wht(0.08); minBtn.layer.cornerRadius = 11;
    [minBtn setTitle:@"−" forState:UIControlStateNormal];
    [minBtn setTitleColor:_ad_wht(0.4) forState:UIControlStateNormal];
    minBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [minBtn addTarget:_ad_targets action:@selector(onMinimize) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:minBtn];
    
    // Sep
    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(14, 38, pw - 28, 1)];
    sep1.backgroundColor = _ad_grnA(0.15); [panel addSubview:sep1];
    
    // Preview box
    UIView *prevBox = [[UIView alloc] initWithFrame:CGRectMake(14, 46, 64, 64)];
    prevBox.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    prevBox.layer.cornerRadius = 12; prevBox.layer.borderWidth = 1;
    prevBox.layer.borderColor = _ad_grnA(0.15).CGColor; prevBox.clipsToBounds = YES;
    
    _ad_previewBox = prevBox;  // حفظ مرجع لصندوق المعاينة
    _ad_previewImg = [[UIImageView alloc] initWithFrame:prevBox.bounds];
    _ad_previewImg.contentMode = UIViewContentModeScaleAspectFill;
    _ad_previewImg.clipsToBounds = YES;
    [prevBox addSubview:_ad_previewImg];
    
    _ad_typeBadge = [[UILabel alloc] initWithFrame:CGRectMake(3, 45, 45, 16)];
    _ad_typeBadge.font = [UIFont boldSystemFontOfSize:8];
    _ad_typeBadge.textColor = [UIColor whiteColor];
    _ad_typeBadge.backgroundColor = _ad_grnA(0.9);
    _ad_typeBadge.textAlignment = NSTextAlignmentCenter;
    _ad_typeBadge.layer.cornerRadius = 4; _ad_typeBadge.clipsToBounds = YES; _ad_typeBadge.hidden = YES;
    [prevBox addSubview:_ad_typeBadge];
    
    UILabel *phLbl = [[UILabel alloc] initWithFrame:prevBox.bounds];
    phLbl.text = @"🖼️"; phLbl.font = [UIFont systemFontOfSize:24]; phLbl.textAlignment = NSTextAlignmentCenter; phLbl.tag = 999;
    [prevBox addSubview:phLbl];
    [panel addSubview:prevBox];
    
    // Import btn
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    importBtn.frame = CGRectMake(84, 46, pw - 112, 64);
    importBtn.backgroundColor = _ad_grnA(0.12); importBtn.layer.cornerRadius = 12;
    importBtn.layer.borderWidth = 1.5; importBtn.layer.borderColor = _ad_grnA(0.4).CGColor;
    [importBtn setTitle:@"+\nاستيراد من الاستوديو" forState:UIControlStateNormal];
    [importBtn setTitleColor:_ad_grnA(0.8) forState:UIControlStateNormal];
    importBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    importBtn.titleLabel.textAlignment = NSTextAlignmentCenter; importBtn.titleLabel.numberOfLines = 2;
    [importBtn addTarget:_ad_targets action:@selector(onImport) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:importBtn];
    
    // Toggle
    UILabel *togLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 120, 150, 22)];
    togLabel.text = @"اعتراض الكاميرا"; togLabel.font = [UIFont systemFontOfSize:13];
    togLabel.textColor = _ad_wht(0.7); [panel addSubview:togLabel];
    
    _ad_toggleBg = [[UIView alloc] initWithFrame:CGRectMake(pw - 58, 118, 44, 24)];
    _ad_toggleBg.backgroundColor = _ad_wht(0.08); _ad_toggleBg.layer.cornerRadius = 12;
    _ad_toggleBg.userInteractionEnabled = YES;
    UITapGestureRecognizer *togTap = [[UITapGestureRecognizer alloc] initWithTarget:_ad_targets action:@selector(onToggleTap:)];
    [_ad_toggleBg addGestureRecognizer:togTap];
    [panel addSubview:_ad_toggleBg];
    
    _ad_toggleKnob = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 20, 20)];
    _ad_toggleKnob.backgroundColor = [UIColor whiteColor]; _ad_toggleKnob.layer.cornerRadius = 10;
    [_ad_toggleBg addSubview:_ad_toggleKnob];
    
    // Swap btn
    _ad_swapBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _ad_swapBtn.frame = CGRectMake(14, 156, pw - 28, 36);
    _ad_swapBtn.backgroundColor = _ad_grnA(0.12); _ad_swapBtn.layer.cornerRadius = 10;
    _ad_swapBtn.layer.borderWidth = 1; _ad_swapBtn.layer.borderColor = _ad_grnA(0.3).CGColor;
    [_ad_swapBtn setTitle:@"📷 كاميرا حقيقية" forState:UIControlStateNormal];
    [_ad_swapBtn setTitleColor:_ad_grnA(0.8) forState:UIControlStateNormal];
    _ad_swapBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_ad_swapBtn addTarget:_ad_targets action:@selector(onSwapTap) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:_ad_swapBtn];
    
    // Sep 2
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(14, 200, pw - 28, 1)];
    sep2.backgroundColor = _ad_grnA(0.15); [panel addSubview:sep2];
    
    // Status
    _ad_statusDot = [[UIView alloc] initWithFrame:CGRectMake(14, 210, 8, 8)];
    _ad_statusDot.backgroundColor = _ad_wht(0.2); _ad_statusDot.layer.cornerRadius = 4;
    [panel addSubview:_ad_statusDot];
    
    _ad_statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(28, 206, pw - 56, 16)];
    _ad_statusLabel.text = @"في الانتظار..."; _ad_statusLabel.font = [UIFont systemFontOfSize:11];
    _ad_statusLabel.textColor = _ad_wht(0.4); [panel addSubview:_ad_statusLabel];
    
    // Footer
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, ph - 16, pw, 12)];
    footer.text = @"AhmadDev © 2026"; footer.font = [UIFont systemFontOfSize:8];
    footer.textColor = _ad_wht(0.2); footer.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:footer];
    
    // Restore state: if media was already loaded, show it
    UIImage *restoreImg = _ad_sourceVideoURL ? _ad_videoThumbnail : _ad_sourceImage;
    if (restoreImg) {
        _ad_previewImg.image = restoreImg;
        _ad_typeBadge.hidden = NO;
        _ad_typeBadge.text = [_ad_mediaType isEqualToString:@"video"] ? @"🎬 فيديو" : @"🖼️ صورة";
        // Remove placeholder
        UIView *prevBox = _ad_previewImg.superview;
        if (prevBox) {
            UIView *placeholder = [prevBox viewWithTag:999];
            [placeholder removeFromSuperview];
        }
        // إذا فيديو — شغّل المعاينة
        if (_ad_sourceVideoURL && _ad_previewBox) {
            [_ad_previewPlayer pause];
            [_ad_previewPlayerLayer removeFromSuperlayer];
            AVURLAsset *pa = [AVURLAsset URLAssetWithURL:_ad_sourceVideoURL options:nil];
            AVPlayerItem *pi = [AVPlayerItem playerItemWithAsset:pa];
            _ad_previewPlayer = [AVPlayer playerWithPlayerItem:pi];
            _ad_previewPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            _ad_previewPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_ad_previewPlayer];
            _ad_previewPlayerLayer.frame = _ad_previewBox.bounds;
            _ad_previewPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [_ad_previewBox.layer addSublayer:_ad_previewPlayerLayer];
            _ad_previewImg.hidden = YES;
            [_ad_previewPlayer play];
            [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:pi queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                [_ad_previewPlayer seekToTime:kCMTimeZero];
                [_ad_previewPlayer play];
            }];
        }
    }
    // Restore toggle state
    if (_ad_toggleOn) {
        _ad_toggleBg.backgroundColor = _ad_grnA(0.8);
        _ad_toggleKnob.frame = CGRectMake(22, 2, 20, 20);
    }
    // Restore status
    _ad_statusLabel.text = _ad_active ? @"البث يعمل" : @"في الانتظار...";
    _ad_statusDot.backgroundColor = _ad_active ? _ad_grn() : _ad_wht(0.2);
    
    [_ad_panelWin.rootViewController.view addSubview:panel];
    _ad_panelView = panel;
}

static void _ad_hidePanel(void) {
    _ad_panelVisible = NO;
    [_ad_panelView removeFromSuperview];
    _ad_panelView = nil;
}

// ═══════════════════════════════════════════════
// AhmadDev Entry Point
// ═══════════════════════════════════════════════
__attribute__((constructor))
static void AhmadDevFakeCamInit(void) {
    NSLog(@"[AhmadDev FakeCam] 🚀 Loading...");
    // Install hooks early
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
        _ad_installHooks();
    });
    // Show FAB after app is fully ready (scene active)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
        _ad_createFab();
        NSLog(@"[AhmadDev FakeCam] ✅ Ready");
    });
}
