ARCHS = arm64
TARGET = iphone:clang:latest:14.0
THEOS_DEVICE_IP =

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeCam

FakeCam_FILES = FakeCam.m
FakeCam_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
FakeCam_FRAMEWORKS = UIKit Foundation AVFoundation Photos CoreMedia CoreVideo ImageIO
FakeCam_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/tweak.mk
