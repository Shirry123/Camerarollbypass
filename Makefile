THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraRollBypass
CameraRollBypass_FILES = Sources/CameraRollBypass/Tweak.x
CameraRollBypass_CFLAGS = -fobjc-arc
CameraRollBypass_FRAMEWORKS = UIKit AVFoundation Photos
CameraRollBypass_FILTER_PLIST = Sources/CameraRollBypass/CameraRollBypass.plist

include $(THEOS_MAKE_PATH)/tweak.mk
