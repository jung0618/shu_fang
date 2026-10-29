/// Unified ShuFang branding. SHUFANG_FLAVOR is a legacy engine-startup
/// compatibility switch during migration, not a product edition boundary.
/// See docs/architecture/shufang-unified.md before adding capability gates.
library;

const String _shuFangFlavorEnv =
    String.fromEnvironment('SHUFANG_FLAVOR', defaultValue: 'public');

const bool _isPrivateBuild =
    _shuFangFlavorEnv == 'private' || _shuFangFlavorEnv == 'PRIVATE';

/// 应用标题（编译期常量）
const String kShuFangWindowTitle = '书坊 ShuFang';

const String kShuFangAppTitle = kShuFangWindowTitle;

const String kShuFangBrand = '书坊';

const String kShuFangPrivateBadge = '私有版';

/// 风味类型
enum ShuFangFlavor {
  /// 开源版
  public,

  /// 私有版（开发者的私人数据 + 训练引擎）
  private,
}

/// 全局 flavor 配置（运行时）
class ShuFangConfig {
  ShuFangConfig._();

  /// 当前风味 (编译期注入)
  static ShuFangFlavor get flavor =>
      _isPrivateBuild ? ShuFangFlavor.private : ShuFangFlavor.public;

  /// 是否为私有版
  static bool get isPrivate => _isPrivateBuild;

  /// 是否为开源版
  static bool get isPublic => !_isPrivateBuild;

  /// 应用标题 (运行时访问)
  static String get appTitle => kShuFangAppTitle;

  /// 窗口标题
  static String get windowTitle => kShuFangWindowTitle;

  /// 品牌副标题
  static String get brand => kShuFangBrand;

  /// 私有版徽标文字
  static String get privateBadge => kShuFangPrivateBadge;

  /// 调试时强制覆盖（仅测试用）
  static void overrideFlavor(ShuFangFlavor f) {
    // 暂未启用：调试时强制覆盖
    assert(() {
      // ignore: avoid_print
      print('[flavor] override -> $f');
      return true;
    }());
  }
}
