# KubeWidget. Run `make help` for targets.

.DEFAULT_GOAL := help
.PHONY: help install uninstall build project preview screenshots icon clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Build, install to ~/Applications and launch
	@scripts/install.sh

uninstall: ## Remove the app, its widgets, data and preferences
	@scripts/uninstall.sh

build: ## Build KubeWidget.app into build/ (SIGN=0 for an unsigned CI build)
	@scripts/build.sh

project: ## Generate KubeWidget.xcodeproj to open in Xcode
	@xcodegen generate

preview: ## Render every widget with your real clusters and SSH hosts to build/preview/
	@scripts/preview.sh build/preview --live

screenshots: ## Re-render the README screenshots (demo data) into docs/images/
	@scripts/preview.sh docs/images

icon: ## Regenerate the app icon (App/Assets.xcassets) from tools/icon/make-icon.swift
	@xcrun swift tools/icon/make-icon.swift

clean: ## Delete build output and the generated Xcode project
	rm -rf build KubeWidget.xcodeproj
