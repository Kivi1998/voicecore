# OpenTypeless 统一任务入口（FND-003）
# README 与文档只引用本文件，禁止维护多套互相冲突的命令。
# 需要完整 Xcode 的目标在 B-001 环境（仅 CLT）下会明确失败并提示。

SWIFT ?= swift
XCODEBUILD ?= xcodebuild
PACKAGES := OpenTypelessDomain OpenTypelessApplication OpenTypelessData OpenTypelessProviders OpenTypelessAudio OpenTypelessPlatform

.PHONY: resolve dev format format-check lint test-packages test-app test e2e archive check-xcode

## 解析 Swift Package 依赖
resolve:
	@for p in $(PACKAGES); do \
		echo "== resolve $$p"; \
		$(SWIFT) package resolve --package-path Packages/$$p || exit 1; \
	done

## 启动 Xcode 开发运行（需要完整 Xcode）
dev: check-xcode
	open OpenTypeless.xcodeproj

## Swift 格式检查（只检查不修改；需要 swiftformat）
format-check:
	swiftformat --lint Packages App --config .swiftformat

## Swift 格式化（就地修改）
format:
	swiftformat Packages App --config .swiftformat

## Swift 静态检查（需要 swiftlint）
lint:
	swiftlint lint --strict

## Swift Package 单元测试（需要 XCTest，即完整 Xcode）
test-packages:
	@for p in $(PACKAGES); do \
		echo "== test $$p"; \
		$(SWIFT) test --package-path Packages/$$p || exit 1; \
	done

## 六包编译（仅 CLT 也可运行）
build-packages:
	@for p in $(PACKAGES); do \
		echo "== build $$p"; \
		$(SWIFT) build --package-path Packages/$$p || exit 1; \
	done

## macOS App 单元测试（需要完整 Xcode）
test-app: check-xcode
	$(XCODEBUILD) test -project OpenTypeless.xcodeproj -scheme OpenTypeless -destination 'platform=macOS'

## 端到端测试（需要完整 Xcode）
e2e: check-xcode
	$(XCODEBUILD) test -project OpenTypeless.xcodeproj -scheme OpenTypelessE2E -destination 'platform=macOS'

## 归档和导出生产应用（需要完整 Xcode 与签名）
archive: check-xcode
	$(XCODEBUILD) archive -project OpenTypeless.xcodeproj -scheme OpenTypeless -archivePath build/OpenTypeless.xcarchive

check-xcode:
	@$(XCODEBUILD) -version >/dev/null 2>&1 || { \
		echo "需要完整 Xcode：安装后执行 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
		exit 1; \
	}
