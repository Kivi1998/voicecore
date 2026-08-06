import Foundation
import OpenTypelessDomain

/// 模型适配层占位标记。
///
/// STT/LLM 任务将在此实现 SpeechProvider 与 RewriteProvider 适配器，
/// 仅使用 URLSession；厂商协议细节不得泄漏到领域层。
public enum OpenTypelessProviders {}
