ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PaopaoJoystick
PaopaoJoystick_FILES = Tweak.xm AppsDump.xm
PaopaoJoystick_CFLAGS = -fobjc-arc
PaopaoJoystick_FRAMEWORKS = UIKit Foundation CoreLocation

include $(THEOS_MAKE_PATH)/tweak.mk
