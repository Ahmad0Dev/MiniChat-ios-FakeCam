// ============================================================
// FakeCam — AhmadDev (c) 2026
// Camera Interception dylib for Minichat
// ============================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

// ============================================================
// XOR String Encoding
// ============================================================
static NSString *_AhmadDev_dec(NSString *hex) {
    NSMutableString *r = [NSMutableString string];
    for (int i = 0; i < hex.length; i += 2) {
        unsigned int b = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]]
            scanHexInt:&b];
        [r appendFormat:@"%c", (char)(b ^ 0x5A)];
    }
    return r;
}

// Encoded string literals
#define _AhmadDev_S(x) _AhmadDev_dec(@x)

// ============================================================
// ============================================================
// Theme Colors
// ============================================================
static UIColor *_AhmadDev_bg(void)       { return [UIColor colorWithRed:28/255.f green:43/255.f blue:59/255.f alpha:1.0]; }
static UIColor *_AhmadDev_grn(void)      { return [UIColor colorWithRed:46/255.f green:204/255.f blue:112/255.f alpha:1.0]; }
static UIColor *_AhmadDev_grnA(float a)  { return [UIColor colorWithRed:46/255.f green:204/255.f blue:112/255.f alpha:a]; }
static UIColor *_AhmadDev_wht(float a)   { return [UIColor colorWithWhite:1.0 alpha:a]; }

// ============================================================
// Copyright Protection — Runtime Integrity Check
// ============================================================
static const char *_AhmadDev_cr_sig = "\x10\x2a\x14\x03\x06\x15\x3f\x12\x06\x0e\x19\x0b\x3f\x0a\x13\x17\x10\x04\x0b\x12\x03";
static const int _AhmadDev_cr_len = 21;

static BOOL _AhmadDev_verifyCR(void) {
    int sum = 0;
    for (int i = 0; i < _AhmadDev_cr_len; i++) sum += (unsigned char)_AhmadDev_cr_sig[i];
    return (sum == 0x19c);
}

// ============================================================
// Global State
// ============================================================
static BOOL _AhmadDev_intercepting = NO;
static BOOL _AhmadDev_active = NO;
static NSString *_AhmadDev_mediaType = @"none";
static UIImage *_AhmadDev_sourceImage = nil;
static NSURL *_AhmadDev_sourceVideoURL = nil;
static UIImage *_AhmadDev_videoThumbnail = nil;
static int _AhmadDev_targetW = 640;
static int _AhmadDev_targetH = 480;
static int _AhmadDev_targetFPS = 30;

// UI State
static UIWindow *_AhmadDev_panelWin = nil;
static UIButton *_AhmadDev_fabBtn = nil;
static UIView *_AhmadDev_panelView = nil;
static UIImageView *_AhmadDev_previewImg = nil;
static UIView *_AhmadDev_previewBox = nil;
static AVPlayer *_AhmadDev_previewPlayer = nil;
static AVPlayerLayer *_AhmadDev_previewPlayerLayer = nil;
static UILabel *_AhmadDev_statusLabel = nil;
static UIView *_AhmadDev_statusDot = nil;
static UIView *_AhmadDev_toggleKnob = nil;
static UIView *_AhmadDev_toggleBg = nil;
static UIButton *_AhmadDev_swapBtn = nil;
static UILabel *_AhmadDev_typeBadge = nil;
static BOOL _AhmadDev_panelVisible = NO;
static BOOL _AhmadDev_toggleOn = NO;

// Frame State
static dispatch_source_t _AhmadDev_frameTimer = nil;
static AVAssetReader *_AhmadDev_videoReader = nil;
static AVAssetReaderTrackOutput *_AhmadDev_videoOutput = nil;
static AVAsset *_AhmadDev_videoAsset = nil;
static CVPixelBufferRef _AhmadDev_imagePixelBuf = NULL;
static __weak id _AhmadDev_currentCapturer = nil;

// Original IMPs
static IMP _AhmadDev_orig_captureOutput = NULL;
static IMP _AhmadDev_orig_switchCamera = NULL;
static IMP _AhmadDev_orig_startWatchingFace = NULL;
static IMP _AhmadDev_orig_startWatchingFaceH = NULL;
static IMP _AhmadDev_orig_stopLocalStream = NULL;
static IMP _AhmadDev_orig_setAYTHidden = NULL;

// ============================================================
// Forward Declarations
// ============================================================
static void _AhmadDev_showPanel(void);
static void _AhmadDev_hidePanel(void);
static void _AhmadDev_stopFrames(void);
static void _AhmadDev_updateStatus(NSString *text, UIColor *color, BOOL active);
static void _AhmadDev_installHooks(void);

// ============================================================
// Logging (encoded prefix)
// ============================================================
static void _AhmadDev_log(NSString *msg) {
    NSLog(@"%@ %@", _AhmadDev_S("011b1e07"), msg);
}

// ============================================================
// Status Update
// ============================================================
static void _AhmadDev_updateStatus(NSString *text, UIColor *color, BOOL active) {
    _AhmadDev_active = active;
    dispatch_async(dispatch_get_main_queue(), ^{
        _AhmadDev_statusLabel.text = text;
        _AhmadDev_statusLabel.textColor = color;
        _AhmadDev_statusDot.backgroundColor = active ? _AhmadDev_grn() : _AhmadDev_wht(0.2);
        [_AhmadDev_fabBtn setTitleColor:active ? _AhmadDev_grn() : _AhmadDev_wht(0.2) forState:UIControlStateNormal];
        if (active) {
            [_AhmadDev_swapBtn setTitle:@"بث وهمي" forState:UIControlStateNormal];
            _AhmadDev_swapBtn.backgroundColor = _AhmadDev_grnA(0.25);
            _AhmadDev_swapBtn.layer.borderColor = _AhmadDev_grnA(0.5).CGColor;
        } else {
            [_AhmadDev_swapBtn setTitle:@"📷 كاميرا حقيقية" forState:UIControlStateNormal];
            _AhmadDev_swapBtn.backgroundColor = _AhmadDev_grnA(0.12);
            _AhmadDev_swapBtn.layer.borderColor = _AhmadDev_grnA(0.3).CGColor;
        }
    });
}

// ============================================================
// Frame Generator — Image to PixelBuffer
// ============================================================
static CVPixelBufferRef _AhmadDev_imageToPixelBuf(UIImage *image, int w, int h) {
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

// ============================================================
// Frame Generator — Make SampleBuffer from PixelBuffer
// ============================================================
static CMSampleBufferRef _AhmadDev_makeSampleBuf(CVPixelBufferRef pxBuf, int fps) {
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

// ============================================================
// Frame Cleanup
// ============================================================
static void _AhmadDev_stopFrames(void) {
    if (_AhmadDev_frameTimer) { dispatch_source_cancel(_AhmadDev_frameTimer); _AhmadDev_frameTimer = nil; }
    [_AhmadDev_videoReader cancelReading];
    _AhmadDev_videoReader = nil; _AhmadDev_videoOutput = nil; _AhmadDev_videoAsset = nil;
    if (_AhmadDev_imagePixelBuf) { CVBufferRelease(_AhmadDev_imagePixelBuf); _AhmadDev_imagePixelBuf = NULL; }
    _AhmadDev_currentCapturer = nil;
    [_AhmadDev_previewPlayer pause]; _AhmadDev_previewPlayer = nil;
    [_AhmadDev_previewPlayerLayer removeFromSuperlayer]; _AhmadDev_previewPlayerLayer = nil;
}

// ============================================================
// Video Reader Helpers
// ============================================================
static void _AhmadDev_prepareVideoReader(AVAsset *asset) {
    [_AhmadDev_videoReader cancelReading];
    _AhmadDev_videoReader = [[AVAssetReader alloc] initWithAsset:asset error:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) return;
    NSDictionary *settings = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(_AhmadDev_targetW),
        (id)kCVPixelBufferHeightKey: @(_AhmadDev_targetH)
    };
    _AhmadDev_videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
    _AhmadDev_videoOutput.supportsRandomAccess = YES;
    [_AhmadDev_videoReader addOutput:_AhmadDev_videoOutput];
    [_AhmadDev_videoReader startReading];
}

static CMSampleBufferRef _AhmadDev_nextVideoFrame(void) {
    if (!_AhmadDev_videoOutput) return NULL;
    CMSampleBufferRef buf = [_AhmadDev_videoOutput copyNextSampleBuffer];
    if (!buf && _AhmadDev_videoAsset) {
        _AhmadDev_prepareVideoReader(_AhmadDev_videoAsset);
        buf = [_AhmadDev_videoOutput copyNextSampleBuffer];
    }
    return buf;
}

// ============================================================
// Hook 1: captureOutput — Frame Interception
// ============================================================
static void _AhmadDev_hooked_captureOutput(id self, SEL _cmd, id output, CMSampleBufferRef sampleBuffer, id connection) {
    if (!_AhmadDev_intercepting || (!_AhmadDev_sourceImage && !_AhmadDev_sourceVideoURL)) {
        if (_AhmadDev_orig_captureOutput)
            ((void(*)(id,SEL,id,CMSampleBufferRef,id))_AhmadDev_orig_captureOutput)(self, _cmd, output, sampleBuffer, connection);
        return;
    }

    if (!_AhmadDev_active) {
        _AhmadDev_updateStatus(
            _AhmadDev_sourceVideoURL ? @"البث يعمل — فيديو" : @"البث يعمل — صورة",
            _AhmadDev_grnA(0.8), YES);
    }

    CMSampleBufferRef fakeBuf = NULL;

    if (_AhmadDev_sourceVideoURL) {
        fakeBuf = _AhmadDev_nextVideoFrame();
    }

    if (fakeBuf) {
        if (_AhmadDev_orig_captureOutput)
            ((void(*)(id,SEL,id,CMSampleBufferRef,id))_AhmadDev_orig_captureOutput)(self, _cmd, output, fakeBuf, connection);
        CFRelease(fakeBuf);
    } else if (_AhmadDev_sourceImage && _AhmadDev_imagePixelBuf) {
        CMSampleBufferRef imgBuf = _AhmadDev_makeSampleBuf(_AhmadDev_imagePixelBuf, _AhmadDev_targetFPS);
        if (imgBuf) {
            if (_AhmadDev_orig_captureOutput)
                ((void(*)(id,SEL,id,CMSampleBufferRef,id))_AhmadDev_orig_captureOutput)(self, _cmd, output, imgBuf, connection);
            CFRelease(imgBuf);
        }
    }
}

// ============================================================
// Hook 2: switchCamera — Block While Active
// ============================================================
static void _AhmadDev_hooked_switchCamera(id self, SEL _cmd) {
    if (_AhmadDev_active) return;
    if (_AhmadDev_orig_switchCamera) ((void(*)(id,SEL))_AhmadDev_orig_switchCamera)(self, _cmd);
}

// ============================================================
// Hook 3: Face Detection — Disabled
// ============================================================
static void _AhmadDev_hooked_startWatchingFace(id self, SEL _cmd) { return; }
static void _AhmadDev_hooked_startWatchingFaceH(id self, SEL _cmd, id handler) { return; }

// ============================================================
// Hook 4: AreYouThereView — Auto-Dismiss
// ============================================================
static void _AhmadDev_hooked_setAYTHidden(id self, SEL _cmd, bool hidden, id model) {
    if (_AhmadDev_orig_setAYTHidden)
        ((void(*)(id,SEL,bool,id))_AhmadDev_orig_setAYTHidden)(self, _cmd, hidden, model);

    if (!hidden) {
        _AhmadDev_log(_AhmadDev_S("1b030e7a0912150d14"));

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
            Class vcbClass = objc_getClass(_AhmadDev_S("050e2e19621733343339323b2e6b6f0c333e3f3519323b2e182f2e2e3534").UTF8String);
            Class aytClass = objc_getClass(_AhmadDev_S("050e2e19621733343339323b2e68691733343339323b2e1b283f03352f0e323f283f0c333f2d").UTF8String);
            if (!vcbClass || !aytClass) return;

            NSMutableArray *stack = [[NSMutableArray alloc] initWithArray:[(UIView *)self subviews]];
            UIView *aytView = nil;
            while (stack.count > 0) {
                UIView *v = [stack lastObject]; [stack removeLastObject];
                if ([v isKindOfClass:aytClass]) { aytView = v; break; }
                [stack addObjectsFromArray:v.subviews];
            }

            if (!aytView) {
                _AhmadDev_log(_AhmadDev_S("1b030e7a34352e7a3c352f343e"));
                return;
            }

            _AhmadDev_log(_AhmadDev_S("1c352f343e7a1b030e"));

            [stack removeAllObjects];
            [stack addObjectsFromArray:aytView.subviews];
            while (stack.count > 0) {
                UIView *v = [stack lastObject]; [stack removeLastObject];
                if ([v isKindOfClass:vcbClass]) {
                    [v setUserInteractionEnabled:YES];
                    _AhmadDev_log(_AhmadDev_S("0c19187a1c150f141e7a717a3f343b38363f3e"));
                    for (UIView *sub in v.subviews) {
                        if ([sub isKindOfClass:[UILabel class]]) {
                            [(UILabel *)sub setText:_AhmadDev_S("1511")];
                            _AhmadDev_log(_AhmadDev_S("163b383f367a77647a1511"));
                        }
                    }
                    return;
                }
                [stack addObjectsFromArray:v.subviews];
            }
            _AhmadDev_log(_AhmadDev_S("0c19187a34352e7a3c352f343e"));
        });
    }
}

// ============================================================
// Hook 5: stopLocalStream — Cleanup
// ============================================================
static void _AhmadDev_hooked_stopLocalStream(id self, SEL _cmd) {
    _AhmadDev_stopFrames();
    _AhmadDev_updateStatus(@"في الانتظار...", _AhmadDev_wht(0.4), NO);
    if (_AhmadDev_orig_stopLocalStream) ((void(*)(id,SEL))_AhmadDev_orig_stopLocalStream)(self, _cmd);
}

// ============================================================
// Hook Installer
// ============================================================
static void _AhmadDev_hookMethod(Class cls, SEL sel, IMP newIMP, IMP *origIMP) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *origIMP = method_getImplementation(m);
    method_setImplementation(m, newIMP);
}

static void _AhmadDev_installHooks(void) {
    Class rtcClass = objc_getClass(_AhmadDev_S("080e19193b373f283b0c333e3f35193b2a2e2f283f28").UTF8String);
    if (!rtcClass) {
        _AhmadDev_log(_AhmadDev_S("0d3f38080e197a34352e7a36353b3e3f3e767a283f2e282333343d747474"));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                        dispatch_get_main_queue(), ^{ _AhmadDev_installHooks(); });
        return;
    }

    _AhmadDev_hookMethod(rtcClass, @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                    (IMP)_AhmadDev_hooked_captureOutput, &_AhmadDev_orig_captureOutput);

    Class vciClass = objc_getClass(_AhmadDev_S("050e2e19621733343339323b2e6b630c333e3f3519323b2e13342e3f283b392e3528").UTF8String);
    if (vciClass) {
        _AhmadDev_hookMethod(vciClass, @selector(switchCamera),
                        (IMP)_AhmadDev_hooked_switchCamera, &_AhmadDev_orig_switchCamera);
        _AhmadDev_hookMethod(vciClass, NSSelectorFromString(_AhmadDev_S("292e3b282e0d3b2e393233343d1c3b393f")),
                        (IMP)_AhmadDev_hooked_startWatchingFace, &_AhmadDev_orig_startWatchingFace);
        _AhmadDev_hookMethod(vciClass, NSSelectorFromString(_AhmadDev_S("292e3b282e0d3b2e393233343d1c3b393f602d332e32123b343e363f2860")),
                        (IMP)_AhmadDev_hooked_startWatchingFaceH, &_AhmadDev_orig_startWatchingFaceH);
        _AhmadDev_hookMethod(vciClass, NSSelectorFromString(_AhmadDev_S("292e352a1635393b36092e283f3b37")),
                        (IMP)_AhmadDev_hooked_stopLocalStream, &_AhmadDev_orig_stopLocalStream);
    }

    Class btnViewCls = objc_getClass(_AhmadDev_S("050e2e19621733343339323b2e686a0c333e3f3519323b2e182f2e2e3534290c333f2d").UTF8String);
    if (btnViewCls) {
        _AhmadDev_hookMethod(btnViewCls, NSSelectorFromString(_AhmadDev_S("293f2e1b283f03352f0e323f283f0c333f2d12333e3e3f346037353e3f3660")),
                        (IMP)_AhmadDev_hooked_setAYTHidden, &_AhmadDev_orig_setAYTHidden);
        _AhmadDev_log(_AhmadDev_S("293f2e1b030e12333e3e3f347a323535313f3e"));
    }

    _AhmadDev_log(_AhmadDev_S("12353531297a3334292e3b36363f3e"));
}

// ============================================================
// Image Picker Delegate
// ============================================================
@interface ADPickerController : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation ADPickerController

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSURL *url = info[UIImagePickerControllerMediaURL];
    UIImage *img = info[UIImagePickerControllerOriginalImage];

    _AhmadDev_stopFrames();
    _AhmadDev_sourceImage = nil;
    _AhmadDev_videoThumbnail = nil;
    _AhmadDev_sourceVideoURL = nil;

    if (url) {
        _AhmadDev_sourceVideoURL = url;
        _AhmadDev_mediaType = @"video";
        AVAsset *a = [AVAsset assetWithURL:url];
        AVAssetImageGenerator *g = [[AVAssetImageGenerator alloc] initWithAsset:a];
        g.appliesPreferredTrackTransform = YES;
        CGImageRef cg = [g copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];
        if (cg) { _AhmadDev_videoThumbnail = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }

        _AhmadDev_videoAsset = [AVAsset assetWithURL:url];
        _AhmadDev_prepareVideoReader(_AhmadDev_videoAsset);
        _AhmadDev_log(_AhmadDev_S("0c333e3f357a283f3b3e3f287a283f3b3e23"));
    } else if (img) {
        _AhmadDev_sourceImage = img;
        _AhmadDev_sourceVideoURL = nil;
        _AhmadDev_mediaType = @"image";
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *previewImg = _AhmadDev_sourceVideoURL ? _AhmadDev_videoThumbnail : _AhmadDev_sourceImage;
        _AhmadDev_previewImg.image = previewImg;
        _AhmadDev_typeBadge.hidden = NO;
        _AhmadDev_typeBadge.text = [_AhmadDev_mediaType isEqualToString:@"video"] ? @"🎬 فيديو" : @"🖼️ صورة";

        UIView *prevBox = _AhmadDev_previewImg.superview;
        if (prevBox) { UIView *ph = [prevBox viewWithTag:999]; [ph removeFromSuperview]; }

        if (_AhmadDev_sourceVideoURL && _AhmadDev_previewBox) {
            [_AhmadDev_previewPlayer pause];
            [_AhmadDev_previewPlayerLayer removeFromSuperlayer];
            AVURLAsset *pa = [AVURLAsset URLAssetWithURL:_AhmadDev_sourceVideoURL options:nil];
            AVPlayerItem *pi = [AVPlayerItem playerItemWithAsset:pa];
            _AhmadDev_previewPlayer = [AVPlayer playerWithPlayerItem:pi];
            _AhmadDev_previewPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;

            _AhmadDev_previewPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_AhmadDev_previewPlayer];
            _AhmadDev_previewPlayerLayer.frame = _AhmadDev_previewBox.bounds;
            _AhmadDev_previewPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [_AhmadDev_previewBox.layer addSublayer:_AhmadDev_previewPlayerLayer];
            _AhmadDev_previewImg.hidden = YES;
            [_AhmadDev_previewPlayer play];

            [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                object:pi queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                    [_AhmadDev_previewPlayer seekToTime:kCMTimeZero];
                    [_AhmadDev_previewPlayer play];
                }];
            _AhmadDev_log(_AhmadDev_S("0c333e3f357a2a283f2c333f2d7a2a363b2333343d"));
        } else {
            [_AhmadDev_previewPlayer pause]; _AhmadDev_previewPlayer = nil;
            [_AhmadDev_previewPlayerLayer removeFromSuperlayer]; _AhmadDev_previewPlayerLayer = nil;
            _AhmadDev_previewImg.hidden = NO;
        }
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

static ADPickerController *_AhmadDev_pickerDel = nil;

// ============================================================
// Pass-Through Overlay Window
// ============================================================
@interface ADOverlayWindow : UIWindow
@end

@implementation ADOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ============================================================
// Gesture Target
// ============================================================
@interface AhmadDevGestureTarget : NSObject
- (void)onFabTap;
- (void)onMinimize;
- (void)onImport;
- (void)onToggleTap:(UITapGestureRecognizer *)g;
- (void)onSwapTap;
- (void)onFabDrag:(UIPanGestureRecognizer *)pan;
- (void)onPanelDrag:(UIPanGestureRecognizer *)pan;
@end

@implementation AhmadDevGestureTarget {
    CGPoint _dragStart;
    BOOL _didDrag;
}

- (void)onFabTap {
    if (_didDrag) { _didDrag = NO; return; }
    if (_AhmadDev_panelVisible) _AhmadDev_hidePanel(); else _AhmadDev_showPanel();
}

- (void)onMinimize { _AhmadDev_hidePanel(); }

- (void)onImport {
    [_AhmadDev_panelWin makeKeyAndVisible];
    _AhmadDev_pickerDel = [[ADPickerController alloc] init];
    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    p.mediaTypes = @[@"public.image", @"public.movie"];
    p.delegate = _AhmadDev_pickerDel;
    [_AhmadDev_panelWin.rootViewController presentViewController:p animated:YES completion:NULL];
}

- (void)onToggleTap:(UITapGestureRecognizer *)g {
    _AhmadDev_toggleOn = !_AhmadDev_toggleOn;
    _AhmadDev_intercepting = _AhmadDev_toggleOn;

    [UIView animateWithDuration:0.3 animations:^{
        _AhmadDev_toggleBg.backgroundColor = _AhmadDev_toggleOn ? _AhmadDev_grnA(0.8) : _AhmadDev_wht(0.08);
        _AhmadDev_toggleKnob.frame = CGRectMake(_AhmadDev_toggleOn ? 22 : 2, 2, 20, 20);
    }];

    if (_AhmadDev_toggleOn && !_AhmadDev_sourceImage && !_AhmadDev_sourceVideoURL) {
        [self onImport];
    }

    if (_AhmadDev_toggleOn) {
        if (_AhmadDev_sourceImage || _AhmadDev_sourceVideoURL) {
            _AhmadDev_updateStatus(@"جاهز — بانتظار المكالمة...", _AhmadDev_grnA(0.6), NO);
            if (_AhmadDev_sourceImage && !_AhmadDev_imagePixelBuf) {
                _AhmadDev_imagePixelBuf = _AhmadDev_imageToPixelBuf(_AhmadDev_sourceImage, _AhmadDev_targetW, _AhmadDev_targetH);
            }
        }
    } else {
        _AhmadDev_stopFrames();
        _AhmadDev_updateStatus(@"في الانتظار...", _AhmadDev_wht(0.4), NO);
    }
}

- (void)onSwapTap {
    if (_AhmadDev_active) {
        _AhmadDev_stopFrames();
        _AhmadDev_updateStatus(@"في الانتظار...", _AhmadDev_wht(0.4), NO);
    }
}

- (void)onFabDrag:(UIPanGestureRecognizer *)pan {
    if (!_AhmadDev_fabBtn) return;
    CGPoint translation = [pan translationInView:_AhmadDev_fabBtn.superview];

    if (pan.state == UIGestureRecognizerStateBegan) {
        _dragStart = _AhmadDev_fabBtn.center;
        _didDrag = NO;
    }

    CGFloat dist = hypot(translation.x, translation.y);
    if (dist > 5) _didDrag = YES;
    if (!_didDrag) return;

    CGPoint newCenter = CGPointMake(_AhmadDev_fabBtn.center.x + translation.x, _AhmadDev_fabBtn.center.y + translation.y);
    CGRect bounds = _AhmadDev_fabBtn.superview.bounds;
    CGFloat hw = _AhmadDev_fabBtn.bounds.size.width / 2;
    CGFloat hh = _AhmadDev_fabBtn.bounds.size.height / 2;
    newCenter.x = MAX(hw, MIN(bounds.size.width - hw, newCenter.x));
    newCenter.y = MAX(hh, MIN(bounds.size.height - hh, newCenter.y));
    _AhmadDev_fabBtn.center = newCenter;
    [pan setTranslation:CGPointZero inView:_AhmadDev_fabBtn.superview];

    if (pan.state == UIGestureRecognizerStateEnded) {
        CGPoint center = _AhmadDev_fabBtn.center;
        CGFloat midX = bounds.size.width / 2;
        CGFloat targetX = (center.x < midX) ? hw + 8 : bounds.size.width - hw - 8;
        [UIView animateWithDuration:0.25 animations:^{
            _AhmadDev_fabBtn.center = CGPointMake(targetX, center.y);
        }];
    }
}

- (void)onPanelDrag:(UIPanGestureRecognizer *)pan {
    if (!_AhmadDev_panelView) return;
    CGPoint translation = [pan translationInView:_AhmadDev_panelView.superview];
    _AhmadDev_panelView.center = CGPointMake(_AhmadDev_panelView.center.x + translation.x, _AhmadDev_panelView.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:_AhmadDev_panelView.superview];
}

@end

static AhmadDevGestureTarget *_AhmadDev_targets = nil;

// ============================================================
// Copyright Footer View
// ============================================================
static UIView *_AhmadDev_createFooter(CGFloat width) {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 36)];
    footer.backgroundColor = [UIColor clearColor];

    // Runtime integrity check
    if (!_AhmadDev_verifyCR()) {
        UILabel *broken = [[UILabel alloc] initWithFrame:footer.bounds];
        broken.text = @"---";
        broken.font = [UIFont systemFontOfSize:7];
        broken.textColor = _AhmadDev_wht(0.1);
        broken.textAlignment = NSTextAlignmentCenter;
        [footer addSubview:broken];
        return footer;
    }

    // Line 1: "By AhmadDev"
    UILabel *line1 = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, width, 16)];
    line1.text = _AhmadDev_S("18237a1b32373b3e1e3f2c");
    line1.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    line1.textColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.3];
    line1.textAlignment = NSTextAlignmentCenter;
    line1.tag = 0xAD1;
    [footer addSubview:line1];

    // Line 2: "www.enjoyteam.app"
    UILabel *line2 = [[UILabel alloc] initWithFrame:CGRectMake(0, 19, width, 14)];
    line2.text = _AhmadDev_S("2d2d2d743f343035232e3f3b37743b2a2a");
    line2.font = [UIFont systemFontOfSize:10];
    line2.textColor = [UIColor colorWithRed:46/255.f green:204/255.f blue:112/255.f alpha:0.4];
    line2.textAlignment = NSTextAlignmentCenter;
    line2.tag = 0xAD3;
    [footer addSubview:line2];

    return footer;
}

// Runtime protection: periodically verify footer hasn't been removed
static void _AhmadDev_protectFooter(void) {
    if (!_AhmadDev_panelView) return;
    UIView *line1 = [_AhmadDev_panelView viewWithTag:0xAD1];
    UIView *line2 = [_AhmadDev_panelView viewWithTag:0xAD3];
    if (!line1 || !line2) {
        // Footer was removed — recreate panel
        _AhmadDev_hidePanel();
        _AhmadDev_showPanel();
    }
}

// ============================================================
// FAB Creation
// ============================================================
static void _AhmadDev_createFab(void) {
    if (_AhmadDev_fabBtn) return;

    _AhmadDev_targets = [[AhmadDevGestureTarget alloc] init];

    ADOverlayWindow *win = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            win = [[ADOverlayWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
            break;
        }
    }
    if (!win) win = [[ADOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.frame = [UIScreen mainScreen].bounds;
    win.windowLevel = UIWindowLevelAlert + 500;
    win.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    win.rootViewController = vc;
    win.hidden = NO;
    _AhmadDev_panelWin = win;

    _AhmadDev_fabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _AhmadDev_fabBtn.frame = CGRectMake(16, 60, 48, 48);
    _AhmadDev_fabBtn.backgroundColor = _AhmadDev_bg();
    _AhmadDev_fabBtn.layer.cornerRadius = 24;
    _AhmadDev_fabBtn.layer.borderWidth = 2;
    _AhmadDev_fabBtn.layer.borderColor = _AhmadDev_grnA(0.6).CGColor;
    [_AhmadDev_fabBtn setTitle:@"\xE2\x97\x8F" forState:UIControlStateNormal];
    [_AhmadDev_fabBtn setTitleColor:_AhmadDev_wht(0.2) forState:UIControlStateNormal];
    _AhmadDev_fabBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    _AhmadDev_fabBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    _AhmadDev_fabBtn.layer.shadowOpacity = 0.3;
    _AhmadDev_fabBtn.layer.shadowOffset = CGSizeMake(0, 2);
    _AhmadDev_fabBtn.layer.shadowRadius = 4;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:_AhmadDev_targets action:@selector(onFabDrag:)];
    [_AhmadDev_fabBtn addGestureRecognizer:pan];
    [_AhmadDev_fabBtn addTarget:_AhmadDev_targets action:@selector(onFabTap) forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:_AhmadDev_fabBtn];
    _AhmadDev_log(_AhmadDev_S("1c1b187a2932352d34"));
}

// ============================================================
// Panel UI
// ============================================================
static void _AhmadDev_showPanel(void) {
    if (_AhmadDev_panelView) return;
    _AhmadDev_panelVisible = YES;

    CGFloat pw = 300, ph = 296;
    CGFloat fabX = _AhmadDev_fabBtn.frame.origin.x;
    CGFloat fabY = _AhmadDev_fabBtn.frame.origin.y + _AhmadDev_fabBtn.frame.size.height + 8;
    CGFloat maxX = [UIScreen mainScreen].bounds.size.width - pw - 8;
    CGFloat px = MAX(8, MIN(maxX, fabX - 120));
    CGFloat py = MAX(8, MIN([UIScreen mainScreen].bounds.size.height - ph - 8, fabY));

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    panel.backgroundColor = _AhmadDev_bg();
    panel.layer.cornerRadius = 20;
    panel.layer.borderWidth = 2;
    panel.layer.borderColor = _AhmadDev_grnA(0.6).CGColor;

    // --- Top Bar (draggable) ---
    UIView *topBarBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 38)];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:_AhmadDev_targets action:@selector(onPanelDrag:)];
    [topBarBg addGestureRecognizer:panelPan];
    [panel addSubview:topBarBg];

    // Logo bars
    UIView *l1 = [[UIView alloc] initWithFrame:CGRectMake(14, 10, 11, 3.5)];
    l1.backgroundColor = _AhmadDev_grn(); l1.layer.cornerRadius = 2;
    l1.transform = CGAffineTransformMakeRotation(-0.35);
    [panel addSubview:l1];
    UIView *l2 = [[UIView alloc] initWithFrame:CGRectMake(14, 16, 14, 3.5)];
    l2.backgroundColor = [UIColor whiteColor]; l2.layer.cornerRadius = 2;
    [panel addSubview:l2];
    UIView *l3 = [[UIView alloc] initWithFrame:CGRectMake(14, 22, 11, 3.5)];
    l3.backgroundColor = _AhmadDev_grn(); l3.layer.cornerRadius = 2;
    l3.transform = CGAffineTransformMakeRotation(0.35);
    [panel addSubview:l3];

    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(32, 10, 20, 22)];
    logo.text = _AhmadDev_S("1b1e"); logo.font = [UIFont boldSystemFontOfSize:11]; logo.textColor = [UIColor whiteColor];
    [panel addSubview:logo];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(54, 10, 150, 22)];
    title.text = @"FakeCam"; title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = _AhmadDev_wht(0.85);
    [panel addSubview:title];

    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame = CGRectMake(pw - 36, 8, 22, 22);
    minBtn.backgroundColor = _AhmadDev_wht(0.08); minBtn.layer.cornerRadius = 11;
    [minBtn setTitle:@"\xE2\x88\x92" forState:UIControlStateNormal];
    [minBtn setTitleColor:_AhmadDev_wht(0.4) forState:UIControlStateNormal];
    minBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [minBtn addTarget:_AhmadDev_targets action:@selector(onMinimize) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:minBtn];

    // --- Separator ---
    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(14, 38, pw - 28, 1)];
    sep1.backgroundColor = _AhmadDev_grnA(0.15); [panel addSubview:sep1];

    // --- Preview Box ---
    UIView *prevBox = [[UIView alloc] initWithFrame:CGRectMake(14, 46, 64, 64)];
    prevBox.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    prevBox.layer.cornerRadius = 12; prevBox.layer.borderWidth = 1;
    prevBox.layer.borderColor = _AhmadDev_grnA(0.15).CGColor; prevBox.clipsToBounds = YES;
    _AhmadDev_previewBox = prevBox;

    _AhmadDev_previewImg = [[UIImageView alloc] initWithFrame:prevBox.bounds];
    _AhmadDev_previewImg.contentMode = UIViewContentModeScaleAspectFill;
    _AhmadDev_previewImg.clipsToBounds = YES;
    [prevBox addSubview:_AhmadDev_previewImg];

    _AhmadDev_typeBadge = [[UILabel alloc] initWithFrame:CGRectMake(3, 45, 45, 16)];
    _AhmadDev_typeBadge.font = [UIFont boldSystemFontOfSize:8];
    _AhmadDev_typeBadge.textColor = [UIColor whiteColor];
    _AhmadDev_typeBadge.backgroundColor = _AhmadDev_grnA(0.9);
    _AhmadDev_typeBadge.textAlignment = NSTextAlignmentCenter;
    _AhmadDev_typeBadge.layer.cornerRadius = 4; _AhmadDev_typeBadge.clipsToBounds = YES; _AhmadDev_typeBadge.hidden = YES;
    [prevBox addSubview:_AhmadDev_typeBadge];

    UILabel *phLbl = [[UILabel alloc] initWithFrame:prevBox.bounds];
    phLbl.text = @"\xF0\x9F\x96\xBC\xEF\xB8\x8F"; phLbl.font = [UIFont systemFontOfSize:24];
    phLbl.textAlignment = NSTextAlignmentCenter; phLbl.tag = 999;
    [prevBox addSubview:phLbl];
    [panel addSubview:prevBox];

    // --- Import Button ---
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    importBtn.frame = CGRectMake(84, 46, pw - 112, 64);
    importBtn.backgroundColor = _AhmadDev_grnA(0.12); importBtn.layer.cornerRadius = 12;
    importBtn.layer.borderWidth = 1.5; importBtn.layer.borderColor = _AhmadDev_grnA(0.4).CGColor;
    [importBtn setTitle:@"+ استيراد من المعرض" forState:UIControlStateNormal];
    [importBtn setTitleColor:_AhmadDev_grnA(0.8) forState:UIControlStateNormal];
    importBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    importBtn.titleLabel.textAlignment = NSTextAlignmentCenter; importBtn.titleLabel.numberOfLines = 2;
    [importBtn addTarget:_AhmadDev_targets action:@selector(onImport) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:importBtn];

    // --- Toggle ---
    UILabel *togLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 120, 150, 22)];
    togLabel.text = @"اعتراض الكاميرا";
    togLabel.font = [UIFont systemFontOfSize:13];
    togLabel.textColor = _AhmadDev_wht(0.7); [panel addSubview:togLabel];

    _AhmadDev_toggleBg = [[UIView alloc] initWithFrame:CGRectMake(pw - 58, 118, 44, 24)];
    _AhmadDev_toggleBg.backgroundColor = _AhmadDev_wht(0.08); _AhmadDev_toggleBg.layer.cornerRadius = 12;
    _AhmadDev_toggleBg.userInteractionEnabled = YES;
    UITapGestureRecognizer *togTap = [[UITapGestureRecognizer alloc] initWithTarget:_AhmadDev_targets action:@selector(onToggleTap:)];
    [_AhmadDev_toggleBg addGestureRecognizer:togTap];
    [panel addSubview:_AhmadDev_toggleBg];

    _AhmadDev_toggleKnob = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 20, 20)];
    _AhmadDev_toggleKnob.backgroundColor = [UIColor whiteColor]; _AhmadDev_toggleKnob.layer.cornerRadius = 10;
    [_AhmadDev_toggleBg addSubview:_AhmadDev_toggleKnob];

    // --- Swap Button ---
    _AhmadDev_swapBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _AhmadDev_swapBtn.frame = CGRectMake(14, 156, pw - 28, 36);
    _AhmadDev_swapBtn.backgroundColor = _AhmadDev_grnA(0.12); _AhmadDev_swapBtn.layer.cornerRadius = 10;
    _AhmadDev_swapBtn.layer.borderWidth = 1; _AhmadDev_swapBtn.layer.borderColor = _AhmadDev_grnA(0.3).CGColor;
    [_AhmadDev_swapBtn setTitle:@"📷 كاميرا حقيقية" forState:UIControlStateNormal];
    [_AhmadDev_swapBtn setTitleColor:_AhmadDev_grnA(0.8) forState:UIControlStateNormal];
    _AhmadDev_swapBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [_AhmadDev_swapBtn addTarget:_AhmadDev_targets action:@selector(onSwapTap) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:_AhmadDev_swapBtn];

    // --- Separator 2 ---
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(14, 200, pw - 28, 1)];
    sep2.backgroundColor = _AhmadDev_grnA(0.15); [panel addSubview:sep2];

    // --- Status ---
    _AhmadDev_statusDot = [[UIView alloc] initWithFrame:CGRectMake(14, 210, 8, 8)];
    _AhmadDev_statusDot.backgroundColor = _AhmadDev_wht(0.2); _AhmadDev_statusDot.layer.cornerRadius = 4;
    [panel addSubview:_AhmadDev_statusDot];

    _AhmadDev_statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(28, 206, pw - 56, 16)];
    _AhmadDev_statusLabel.text = @"في الانتظار...";
    _AhmadDev_statusLabel.font = [UIFont systemFontOfSize:11];
    _AhmadDev_statusLabel.textColor = _AhmadDev_wht(0.4); [panel addSubview:_AhmadDev_statusLabel];

    // --- Copyright Footer ---
    UIView *footerContainer = [[UIView alloc] initWithFrame:CGRectMake(14, 226, pw - 28, 36)];
    UIView *footer = _AhmadDev_createFooter(pw - 28);
    [footer setFrame:footerContainer.bounds];
    [footerContainer addSubview:footer];
    [panel addSubview:footerContainer];

    // --- Restore State ---
    UIImage *restoreImg = _AhmadDev_sourceVideoURL ? _AhmadDev_videoThumbnail : _AhmadDev_sourceImage;
    if (restoreImg) {
        _AhmadDev_previewImg.image = restoreImg;
        _AhmadDev_typeBadge.hidden = NO;
        _AhmadDev_typeBadge.text = [_AhmadDev_mediaType isEqualToString:@"video"] ? @"🎬 فيديو" : @"🖼️ صورة";
        UIView *pb = _AhmadDev_previewImg.superview;
        if (pb) { UIView *p = [pb viewWithTag:999]; [p removeFromSuperview]; }

        if (_AhmadDev_sourceVideoURL && _AhmadDev_previewBox) {
            [_AhmadDev_previewPlayer pause];
            [_AhmadDev_previewPlayerLayer removeFromSuperlayer];
            AVURLAsset *pa = [AVURLAsset URLAssetWithURL:_AhmadDev_sourceVideoURL options:nil];
            AVPlayerItem *pi = [AVPlayerItem playerItemWithAsset:pa];
            _AhmadDev_previewPlayer = [AVPlayer playerWithPlayerItem:pi];
            _AhmadDev_previewPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            _AhmadDev_previewPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:_AhmadDev_previewPlayer];
            _AhmadDev_previewPlayerLayer.frame = _AhmadDev_previewBox.bounds;
            _AhmadDev_previewPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [_AhmadDev_previewBox.layer addSublayer:_AhmadDev_previewPlayerLayer];
            _AhmadDev_previewImg.hidden = YES;
            [_AhmadDev_previewPlayer play];
            [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                object:pi queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                    [_AhmadDev_previewPlayer seekToTime:kCMTimeZero];
                    [_AhmadDev_previewPlayer play];
                }];
        }
    }

    if (_AhmadDev_toggleOn) {
        _AhmadDev_toggleBg.backgroundColor = _AhmadDev_grnA(0.8);
        _AhmadDev_toggleKnob.frame = CGRectMake(22, 2, 20, 20);
    }

    _AhmadDev_statusLabel.text = _AhmadDev_active ? @"البث يعمل" : @"في الانتظار...";
    _AhmadDev_statusDot.backgroundColor = _AhmadDev_active ? _AhmadDev_grn() : _AhmadDev_wht(0.2);

    [_AhmadDev_panelWin.rootViewController.view addSubview:panel];
    _AhmadDev_panelView = panel;

    // Start footer protection timer
    [NSTimer scheduledTimerWithTimeInterval:5.0 target:[NSBlockOperation blockOperationWithBlock:^{
        _AhmadDev_protectFooter();
    }] selector:@selector(main) userInfo:nil repeats:YES];
}

static void _AhmadDev_hidePanel(void) {
    _AhmadDev_panelVisible = NO;
    [_AhmadDev_panelView removeFromSuperview];
    _AhmadDev_panelView = nil;
}

// ============================================================
// Entry Point
// ============================================================
__attribute__((constructor))
static void FakeCamInit(void) {
    _AhmadDev_log(_AhmadDev_S("1c3b313f193b377a36353b3e3f3e"));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ _AhmadDev_installHooks(); });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
        _AhmadDev_createFab();
        _AhmadDev_log(_AhmadDev_S("083f3b3e23"));
    });
}
