# FakeCam — AhmadDev Camera Interception Framework

> أداة اعتراض كاميرا لتطبيق Minichat على iOS
> متوافق مع TrollStore / بدون جيلبريك

---

## البنية

```
FakeCam/
├── dylib/
│   ├── FakeCam.m          ← السورس الرئيسي (ObjC, arm64)
│   ├── FakeCam.dylib      ← الـ dylib الجاهز
│   ├── FakeCam.plist      ← Bundle filter (com.minichat.ios)
│   ├── Makefile           ← بناء Theos
│   └── logo_base64.inc    ← اللوجو المدمج (base64, غير مستخدم حالياً)
└── README.md              ← هذا الملف
```

---

## الوظائف

### 1. اعتراض الصور والفيديو (Camera Interception)

**الهدف:** استبدال بث الكاميرا الحقيقي بصورة أو فيديو وهمي أثناء مكالمات الفيديو.

**آلية العمل:**
- Hook على `RTCCameraVideoCapturer.captureOutput:didOutputSampleBuffer:fromConnection:`
- كل إطار حقيقي يمر من الكاميرا → يُستبدل بإطار وهمي
- الفيديو: يُقرأ إطار بإطار من ملف الفيديو (AVAssetReader) مع loop تلقائي
- الصورة: تُحوّل لـ CVPixelBufferRef وتُبث كإطار ثابت
- إذا فشل الإطار الوهمي → يُسقط الإطار الحقيقي (أسود أفضل من كاميرا حقيقية)

**الأولوية:**
1. فيديو (إذا موجود) ← إطارات حقيقية من ملف الفيديو
2. صورة (إذا لا يوجد فيديو) ← إطار ثابت
3. إسقاط (إذا فشل الكل) ← شاشة سوداء

### 2. واجهة التحكم (Control Panel)

**عناصر الواجهة:**

| العنصر | الوظيفة |
|--------|---------|
| FAB (زر عائم ●) | فتح/إغلاق لوحة التحكم |
| عنوان "FakeCam" | اسم الأداة |
| معاينة (Preview) | عرض الصورة/الفيديو المحدد |
| زر 🖼️ | اختيار صورة من المعرض |
| زر + استيراد من المعرض | استيراد فيديو |
| زر التصغير (−) | إخفاء اللوحة |
| تبديل (Toggle) | تفعيل/إيقاف الاعتراض |
| زر "📷 كاميرا حقيقية" / "بث وهمي" | التبديل بين الوضعين |
| شارة النوع | 🎬 فيديو أو 🖼️ صورة |
| الحالة | نقطة + نص (في الانتظار... / البث يعمل) |
| الحقوق | By AhmadDev + www.enjoyteam.app |

**الألوان:**
- خلفية: RGB(28, 43, 59) — أزرق غامق
- أخضر AhmadDev: RGB(46, 204, 112) — للعناصر النشطة
- شفافيات متعددة (_AhmadDev_wht, _AhmadDev_grnA)

### 3. حماية الحقوق (Copyright Protection)

**الحقوق:**
```
By AhmadDev
www.enjoyteam.app
```

**آلية الحماية:**
1. **XOR Encoding (0x5A):** نصوص الحقوق مشفّرة في الباينري
   - `By AhmadDev` ← `_AhmadDev_S("18237a1b32373b3e1e3f2c")`
   - `www.enjoyteam.app` ← `_AhmadDev_S("2d2d2d743f343035232e3f3b37743b2a2a")`
   
2. **Runtime Integrity Check:** توقيع ثابت `_AhmadDev_cr_sig` مجموعه = 0x19C
   - إذا التوقيع اتغيّر → الفوتر يظهر "---" فقط
   
3. **Footer Protection Timer:** كل 5 ثواني يفحص وجود الحقوق
   - إذا حُذفت ← يُعيد بناء اللوحة كاملة
   
4. **AhmadDev Deep Watermark:** اسم AhmadDev في كل شيء:
   - كل المتغيرات: `_AhmadDev_sourceImage`, `_AhmadDev_active`...
   - كل الدوال: `_AhmadDev_hooked_captureOutput`, `_AhmadDev_createFab`...
   - الكلاس: `AhmadDevGestureTarget`
   - 5 نصوص watermark مخفية في الباينري (496 مرة في السورس، 185 في الباينري)

5. **Tag-based Detection:** الحقوق تستخدم tags فريدة (0xAD1, 0xAD3) للحماية

---

## البنية الداخلية للكود

### الأقسام (14 قسم):

```
1. Headers & Imports
2. XOR String Encoding (_AhmadDev_dec)
3. Copyright Protection (_AhmadDev_cr_sig, _AhmadDev_verifyCR)
4. Theme Colors (_AhmadDev_bg, _AhmadDev_grn, _AhmadDev_wht)
5. Global State (متغيرات الحالة والـ UI)
6. Status Updates (_AhmadDev_updateStatus)
7. Frame Generator (_AhmadDev_imageToPixelBuf, _AhmadDev_makeSampleBuf)
8. Video Reader (_AhmadDev_prepareVideoReader, _AhmadDev_nextVideoFrame)
9. Hooks (_AhmadDev_hooked_captureOutput, switchCamera, face detection)
10. AreYouThere Handler (تمكين زر OK)
11. Image Picker Delegate (استيراد الصور/الفيديو)
12. Copyright Footer (_AhmadDev_createFooter, _AhmadDev_protectFooter)
13. UI Creation (FAB + Panel + جميع العناصر)
14. Entry Point (__attribute__((constructor)) AhmadDev_CameraInit)
```

### الـ Hooks المثبتة:

| Hook | الهدف | الوظيفة |
|------|-------|---------|
| `RTCCameraVideoCapturer.captureOutput:didOutputSampleBuffer:fromConnection:` | WebRTC | استبدال الإطارات |
| `RTCCameraVideoCapturer.switchCamera` | WebRTC | منع التبديل أثناء البث |
| `VideoChatInteractor.startWatchingFace` | Minichat | تعطيل كشف الوجه (1) |
| `VideoChatInteractor.startWatchingFace:withHandler:` | Minichat | تعطيل كشف الوجه (2) |
| `VideoChatInteractor.stopLocalStream` | Minichat | منع إيقاف البث |
| `VideoChatButtonsView.setAreYouThereViewHidden:model:` | Minichat | تمكين زر OK |

---

## البناء

### المتطلبات:
- Theos: `/opt/theos`
- SDK: iPhoneOS14.5.sdk
- Target: arm64, iOS 14.0+

### الأوامر:
```bash
cd /opt/ios/projects/FakeCam/dylib
export THEOS=/opt/theos
make clean && make
```

### الناتج:
```
.theos/obj/debug/FakeCam.dylib  (~140KB)
```

---

## التثبيت

### عبر TrollStore:
1. انسخ `FakeCam.dylib` إلى `/var/containers/Bundle/Application/UUID/Minichat.app/Frameworks/`
2. أو استخدم insert_dylib/liberty لحقن الـ dylib في الـ IPA

### مع Binary Patch (عداد فوري):
1. ثبّت الباينري المعدّل (4 بايت في offset 0x52AAF4)
2. ثبّت FakeCam.dylib فوقه
3. الاثنان يشتغلان مع بعض بدون تعارض

---

## Binary Patch — تسريع العداد

### المشكلة:
- تحذير "يرغب مستخدمو الدردشة في معرفة الأشخاص الذين يتحدثون معهم"
- العداد يبدأ من 79 ثانية (أو أكثر) وينتهي تنازلياً
- **لا يمكن التحكم فيه عبر dylib hook** — Swift stored properties

### الحل:
- Binary Patch: 4 بايت في offset `0x52AAF4`
- قبل: `A9 BC 5F F8` = `STP x28,x27,[sp,-0x40]!` (بداية start_countdown)
- بعد: `17 FF FF 9D` = `B finish_countdown` (إنهاء فوري)

### لماذا الـ Dylib Hook فشل:
- `globalTimeEnd`, `timer`, `enableTick`, `tick` — كلها **Swift stored properties**
- تُقرأ/تُكتب عبر **ivar offsets مباشرة** (`*(long*)(self + offset)`)
- **ليس** عبر ObjC methods — KVC يسكّت بس ما يغيّر شي
- `class_getInstanceVariable("globalTimeEnd")` يرجع `NULL`
- جربنا +10 طرق مختلفة — كلها فشلت

### التفاصيل التقنية:
```
FUN_10052aaf4 (start countdown) @ VM 0x10052AAF4, File 0x52AAF4
  - تضرب القيمة × 2
  - تكتب globalTimeEnd
  - تغيّر نص الزر
  - تُنشئ NSTimer كل 1 ثانية

FUN_10052a968 (finish countdown) @ VM 0x10052A968, File 0x52A968
  - timer.invalidate()
  - timer = nil
  - globalTimeEnd = 0
  - button.userInteractionEnabled = YES
  - نص الزر → "OK"

Branch: 0x10052AAF4 → 0x10052A968
  الفرق = -0x18C = -396 bytes = -99 instructions
  arm64 B: 17 FF FF 9D
```

---

## ملاحظات مهمة

1. **لا تستخدم vm_protect على iOS code pages** — الكود موقّع وما يُعدّل وقت التشغيل
2. **Binary Patching > Hooking** — أبسط وأضمن للتغييرات العميقة
3. **Swift stored properties ≠ ObjC ivars** — لا تُسجّل في runtime metadata
4. **الـ timer يفحص الحقوق كل 5 ثواني** — حذف الحقوق = إعادة بناء اللوحة
5. **AhmadDev مدمج عميق** — 496 مرة في السورس، 185 في الباينري النهائي

---

## الترخيص

© AhmadDev 2026 — جميع الحقوق محفوظة
www.enjoyteam.app
