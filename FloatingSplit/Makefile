ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PaopaoFloatingSplit
PaopaoFloatingSplit_FILES = Tweak.xm
PaopaoFloatingSplit_CFLAGS = -fobjc-arc
PaopaoFloatingSplit_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
