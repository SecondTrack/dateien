# Dateien — WLAN-Dateiverwaltung im Browser für iPod touch 4 (iOS 6.1, ARMv7), Theos.
TARGET = iphone:clang:7.1:5.0
ARCHS  = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Dateien

Dateien_FILES  = $(wildcard src/*.m) $(wildcard src/*.c)
Dateien_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation ImageIO AssetsLibrary AVFoundation CoreMedia
Dateien_CFLAGS  = -fobjc-arc -O2 -Wall

include $(THEOS_MAKE_PATH)/application.mk

# root-Helfer zum Installieren/Entfernen von Apps (setuid root, Rechte setzt DEBIAN/postinst)
TOOL_NAME = fmpkg
fmpkg_FILES = tool/fmpkg.c
fmpkg_CFLAGS = -O2 -Wall
fmpkg_FRAMEWORKS = CoreFoundation
fmpkg_LIBRARIES = z
fmpkg_INSTALL_PATH = /Applications/Dateien.app

include $(THEOS_MAKE_PATH)/tool.mk

# Browser-Oberfläche (web/) als C-Arrays einbetten
src/FMWeb.h: web/index.html web/app.js tools/mkweb.sh
	sh tools/mkweb.sh

before-all:: src/FMWeb.h
