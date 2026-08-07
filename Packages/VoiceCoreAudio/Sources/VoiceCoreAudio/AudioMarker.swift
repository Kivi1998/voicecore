import Foundation
import VoiceCoreDomain

/// 音频采集与编码包占位标记。
///
/// PLAT-003 将在此实现 AVFoundation 麦克风采集与持续写盘；
/// 不得把 AVFoundation 类型泄漏到领域层接口。
public enum VoiceCoreAudio {}
