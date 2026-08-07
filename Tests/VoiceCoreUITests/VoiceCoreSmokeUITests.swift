import XCTest

/// TEST-002：主界面、状态、关键交互、密钥遮罩与键盘路径 XCUITest。
final class VoiceCoreSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryPagesAndEmptyHistorySnapshot() {
        let app = launch(scenario: "empty")
        for identifier in ["sidebar.dashboard", "sidebar.history", "sidebar.dictionary"] {
            XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 5), "缺少导航入口 \(identifier)")
        }

        element("sidebar.history", in: app).click()
        XCTAssertTrue(element("history.empty", in: app).waitForExistence(timeout: 5), "空历史状态未出现")
        attachSnapshot(app, name: "历史空态")
    }

    @MainActor
    func testStartupErrorStateSnapshot() {
        let app = launch(scenario: "startup-error")
        XCTAssertTrue(element("startup.error", in: app).waitForExistence(timeout: 5), "启动错误态未出现")
        XCTAssertTrue(app.staticTexts["无法启动"].exists)
        XCTAssertTrue(app.staticTexts["界面测试模拟的数据初始化失败。"].exists)
        attachSnapshot(app, name: "启动错误态")
    }

    @MainActor
    func testHistoryDeletionRequiresConfirmation() {
        let app = launch(scenario: "history-record")
        element("sidebar.history", in: app).click()

        let recordID = "11111111-1111-1111-1111-111111111111"
        let recordButton = app.buttons["history.record.toggle.\(recordID)"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "测试记录未加载")
        XCTAssertTrue(recordButton.label.contains("这是用于界面验收的测试记录"), "记录摘要不正确")
        recordButton.click()

        let deleteButton = element("history.record.delete.\(recordID)", in: app)
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "展开后未出现删除按钮")
        deleteButton.click()

        XCTAssertTrue(app.staticTexts["删除这条记录？"].waitForExistence(timeout: 3), "删除确认未出现")
        XCTAssertTrue(app.staticTexts["将同时删除数据库记录与录音文件，此操作不可撤销。"].exists)
        attachSnapshot(app, name: "历史删除确认")
        app.sheets.buttons["取消"].click()
        XCTAssertTrue(recordButton.exists, "取消删除后记录不应消失")
    }

    @MainActor
    func testAPIKeyUsesSecureFieldAndNativeSettingsWindow() {
        let app = launch(scenario: "empty")

        // 通过原生应用菜单打开设置；页签控件在不同 macOS 版本可能映射为按钮或单选按钮。
        let settingsMenuItem = app.menuBars.menuItems["设置…"]
        XCTAssertTrue(settingsMenuItem.waitForExistence(timeout: 5), "缺少原生设置菜单项")
        settingsMenuItem.click()
        let providersTab = element(L10nValue.providers, in: app)
        XCTAssertTrue(providersTab.waitForExistence(timeout: 5), "设置窗口缺少模型页签")
        providersTab.click()
        XCTAssertTrue(element("settings.providers", in: app).waitForExistence(timeout: 5), "模型配置页未出现")
        app.buttons["新增语音模型…"].click()

        let secretField = app.secureTextFields["provider.api-key"]
        XCTAssertTrue(secretField.waitForExistence(timeout: 5), "API 密钥未使用 SecureField")
        let secret = "test-secret-must-stay-masked"
        secretField.click()
        secretField.typeText(secret)

        XCTAssertFalse(app.staticTexts[secret].exists, "完整密钥不应作为普通文本出现")
        XCTAssertNotEqual(secretField.value as? String, secret, "SecureField 的可访问值不得暴露完整密钥")
        attachSnapshot(app, name: "模型密钥遮罩")
    }

    @MainActor
    func testKeyboardArrowNavigationSwitchesSidebarPage() {
        let app = launch(scenario: "empty")
        let dashboard = element("sidebar.dashboard", in: app)
        dashboard.click()

        // 侧栏使用系统 List 键盘行为；向下键应从首页移动到历史记录。
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(element("history.empty", in: app).waitForExistence(timeout: 5), "方向键未切换到历史记录")
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["VOICECORE_UI_TESTING"] = "1"
        app.launchEnvironment["VOICECORE_UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["VOICECORE_UI_TEST_RUN_ID"] = "\(scenario)-\(UUID().uuidString)"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "启动后 15 秒内未出现窗口")
        addTeardownBlock { app.terminate() }
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func attachSnapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum L10nValue {
    static let providers = "模型"
}
