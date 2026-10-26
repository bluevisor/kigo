# Builds Kigo and its hotkey filter. Run on Haiku.
#   make            build/Kigo and build/KigoHotkey
#   make package    dist/kigo-<version>-<rev>-<arch>.hpkg
#   make install    the package into ~/config/packages, replacing any older one
#   make run        (re)start the built Kigo

CXX ?= g++
CXXFLAGS ?= -O2 -g
VERSION := $(shell cat VERSION)
CXXFLAGS += -std=c++17 -Wall -Wno-multichar -DKIGO_VERSION='"$(VERSION)"'
BUILD := build

SOURCES := $(wildcard src/*.cpp)
OBJECTS := $(SOURCES:src/%.cpp=$(BUILD)/%.o)

APP := $(BUILD)/Kigo
FILTER := $(BUILD)/KigoHotkey
PACKAGES := $(shell finddir B_USER_PACKAGES_DIRECTORY 2>/dev/null)

all: $(APP) $(FILTER)

$(BUILD)/%.o: src/%.cpp src/*.h VERSION
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD)/Kigo.rsrc: haiku/Kigo.rdef
	@mkdir -p $(BUILD)
	rc -o $@ $<

$(APP): $(OBJECTS) $(BUILD)/Kigo.rsrc
	$(CXX) -o $@ $(OBJECTS) -lbe
	xres -o $@ $(BUILD)/Kigo.rsrc
	mimeset -f $@

# Filters resolve BInputServerFilter against the input_server executable.
$(FILTER): hotkey/HotkeyFilter.cpp src/Kigo.h
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) -shared -fPIC -o $@ $< -lbe /boot/system/servers/input_server

package: all
	haiku/package.sh

# Swapping the package stops a running Kigo; start the new one hidden. Kigo
# installs the hotkey filter itself (copy, then rename: never rewrite the
# loaded filter in place, which crashed the input_server on 2026-10-25).
install: package
	-haiku/stop.sh
	rm -f $(PACKAGES)/kigo-*.hpkg
	cp $$(ls -t dist/kigo-$(VERSION)-*.hpkg | head -1) $(PACKAGES)/
	sleep 3
	/boot/home/config/apps/Kigo --background > /dev/null 2>&1 &

run: $(APP)
	-haiku/stop.sh
	$(APP) &

clean:
	rm -rf $(BUILD) dist

.PHONY: all package install run clean
