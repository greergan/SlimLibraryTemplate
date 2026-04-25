BUILD_DIR := build
INSTALL_PREFIX ?= /usr
CMAKE := cmake
DIST_DIR ?= .
LOCAL_SRC ?= ON;
RELEASE_TYPE ?= DEBUG

IS_DEBIAN := $(shell test -f /etc/debian_version && echo "yes")
IS_REDHAT := $(shell test -f /etc/redhat-release && echo "yes")

ARCH_RAW := $(shell uname -m)
ifeq ($(ARCH_RAW),x86_64)
	ARCH := x86_64
else ifeq ($(ARCH_RAW),amd64)
	ARCH := x86_64
else ifeq ($(ARCH_RAW),i386)
	ARCH := x86
else ifeq ($(ARCH_RAW),i686)
	ARCH := x86
else ifeq ($(ARCH_RAW),aarch64)
	ARCH := arm64
else ifeq ($(ARCH_RAW),armv7l)
	ARCH := arm
else
	ARCH := unknown
endif

.PHONY: all configure build install test deb rpm packages clean

all: build

configure:
	$(CMAKE) -S . -B $(BUILD_DIR) \
		-DCMAKE_BUILD_TYPE=$(RELEASE_TYPE) \
		-DCMAKE_INSTALL_PREFIX=$(INSTALL_PREFIX) \
		-DCPACK_OUTPUT_FILE_PREFIX=$(DIST_DIR) \
		-DSLIM_USE_LOCAL_SOURCE=$(LOCAL_SRC)

build: configure
	$(CMAKE) --build $(BUILD_DIR)

install:
	@if [ "$(IS_DEBIAN)" = "yes" ]; then \
		$(MAKE) deb; \
		PKG=$$(ls -1t *.deb 2>/dev/null | sort --reverse | head -n 1); \
		if [ -n "$$PKG" ]; then \
			echo "Installing $$PKG"; \
			dpkg -i "$$PKG"; \
		else \
			echo "No .deb produced"; \
			exit 1; \
		fi; \
	elif [ "$(IS_REDHAT)" = "yes" ]; then \
		$(MAKE) rpm; \
		PKG=$$(ls *.rpm 2>/dev/null | sort --reverse | head -n 1); \
		if [ -n "$$PKG" ]; then \
			echo "Installing $$PKG"; \
			rpm -i "$$PKG"; \
		else \
			echo "No .rpm produced"; \
			exit 1; \
		fi; \
	else \
		echo "Unsupported platform"; \
		exit 1; \
	fi;

deb: build
	cd $(BUILD_DIR) && cpack -G DEB

rpm: build
	cd $(BUILD_DIR) && cpack -G RPM

packages:
	cd $(BUILD_DIR) && for f in DEB RPM; do cpack -G $$f; done

clean:
	rm -rf $(BUILD_DIR)
	rm -f *.deb *.rpm