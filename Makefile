# CodecSwitch build/package helper.
#
#   make            run unit tests
#   make test       run Perl unit tests
#   make dist       create dist/CodecSwitch/
#   make bundle     create dist/CodecSwitch-<version>.zip + .tar.gz
#   make install PLUGINS_DIR=/path/to/lms/Plugins
#   make smoke      run Docker smoke tests for LMS 9.0.0 and 9.1.1

VERSION ?= $(shell head -n 1 VERSION 2>/dev/null | tr -d '[:space:]')
RELEASE_BASE ?= https://github.com/BeyondandSharp/lms-plugin-CodecSwitch/releases/download
RELEASE_TAG_PREFIX ?= v

BUILD := build
DIST  := dist/CodecSwitch
PERL  ?= perl
PROVE ?= prove
ZIP   ?= zip

MODULES := \
	lib/Plugins/CodecSwitch/Plugin.pm \
	lib/Plugins/CodecSwitch/Settings.pm \
	lib/Plugins/CodecSwitch/PlayerSettings.pm \
	lib/Plugins/CodecSwitch/Config.pm \
	lib/Plugins/CodecSwitch/Toolchain.pm \
	lib/Plugins/CodecSwitch/CommandBuilder.pm \
	lib/Plugins/CodecSwitch/Profiles.pm \
	lib/Plugins/CodecSwitch/Hooks.pm \
	lib/Plugins/CodecSwitch/Capabilities.pm \
	lib/Plugins/CodecSwitch/Orchestrator.pm

.PHONY: all test render-version repo sync-version bump dist bundle install verify-dist smoke lms-patch-check lms-patch lms-patched-image clean

all: test

render-version:
	@$(PERL) tools/sync-version.pl \
		--version "$(VERSION)" \
		--release-base "$(RELEASE_BASE)" \
		--tag-prefix "$(RELEASE_TAG_PREFIX)" \
		--output-dir "$(BUILD)"

repo: render-version
	@echo "Catalog: $(BUILD)/repo.xml"

sync-version: render-version

bump:
	@printf '%s\n' "$(VERSION)" > VERSION
	@$(MAKE) render-version VERSION="$(VERSION)"

test:
	@$(PERL) -Ilib -It/lib -c lib/Plugins/CodecSwitch/Config.pm
	@$(PERL) -Ilib -It/lib -c lib/Plugins/CodecSwitch/CommandBuilder.pm
	@$(PROVE) -l -It/lib t

dist: render-version
	@rm -rf "$(DIST)"
	@mkdir -p "$(DIST)"
	@cp -p "$(BUILD)/install.xml" strings.txt README.md README.zh-CN.md LICENSE "$(DIST)/"
	@cp -Rp patches "$(DIST)/"
	@cp -Rp lib HTML "$(DIST)/"
	@find "$(DIST)" -type d -exec chmod 755 {} +
	@find "$(DIST)" -type f -exec chmod 644 {} +
	@echo "Release folder: $(DIST)"

bundle: dist
	@rm -f "dist/CodecSwitch-$(VERSION).zip" "dist/CodecSwitch-$(VERSION).tar.gz"
	@(cd dist && $(ZIP) -qr "CodecSwitch-$(VERSION).zip" CodecSwitch)
	@tar -C dist -czf "dist/CodecSwitch-$(VERSION).tar.gz" CodecSwitch
	@echo "Archives: dist/CodecSwitch-$(VERSION).zip dist/CodecSwitch-$(VERSION).tar.gz"

verify-dist:
	@test -f "$(DIST)/install.xml" || (echo "missing dist; run make dist" >&2; exit 1)
	@grep -q "<version>$(VERSION)</version>" "$(DIST)/install.xml" || (echo "install.xml version mismatch" >&2; exit 1)
	@test -f "$(DIST)/lib/Plugins/CodecSwitch/Plugin.pm" || (echo "missing plugin module" >&2; exit 1)
	@test -f "$(DIST)/HTML/EN/plugins/CodecSwitch/settings/basic.html" || (echo "missing settings page" >&2; exit 1)
	@test -f "$(DIST)/patches/lms/bitrate-codecs.patch" || (echo "missing LMS UI patch" >&2; exit 1)
	@for m in $(MODULES); do \
		test -f "$(DIST)/$$m" || (echo "missing $$m" >&2; exit 1); \
		$(PERL) -I"$(DIST)/lib" -It/lib -c "$(DIST)/$$m" || exit 1; \
	done
	@echo "dist verified"

lms-patch-check:
	@test -n "$(LMS_ROOT)" || (echo "usage: make lms-patch-check LMS_ROOT=/path/to/lms" >&2; exit 1)
	@sh tools/apply-lms-patch.sh "$(LMS_ROOT)" --check

lms-patch:
	@test -n "$(LMS_ROOT)" || (echo "usage: make lms-patch LMS_ROOT=/path/to/lms" >&2; exit 1)
	@sh tools/apply-lms-patch.sh "$(LMS_ROOT)"

lms-patched-image:
	@sh tools/build-lms-patched-image.sh 9.1.1
	@sh tools/build-lms-patched-image.sh 9.0.0

install: dist
	@test -n "$(PLUGINS_DIR)" || (echo "usage: make install PLUGINS_DIR=/path/to/lms/Plugins" >&2; exit 1)
	@rm -rf "$(PLUGINS_DIR)/CodecSwitch"
	@cp -a "$(DIST)" "$(PLUGINS_DIR)/CodecSwitch"
	@echo "Installed to $(PLUGINS_DIR)/CodecSwitch"

smoke: dist
	@sh tools/lms-smoke.sh

clean:
	@rm -rf "$(BUILD)" dist
