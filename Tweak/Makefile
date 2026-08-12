ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PaopaoJoystickSpringBoard PaopaoJoystickAppsDump

PaopaoJoystickSpringBoard_FILES = Tweak.xm
PaopaoJoystickSpringBoard_CFLAGS = -fobjc-arc
PaopaoJoystickSpringBoard_FRAMEWORKS = UIKit Foundation MapKit CoreLocation

PaopaoJoystickAppsDump_FILES = AppsDump.xm
PaopaoJoystickAppsDump_CFLAGS = -fobjc-arc
PaopaoJoystickAppsDump_FRAMEWORKS = UIKit Foundation CoreLocation

include $(THEOS_MAKE_PATH)/tweak.mk
