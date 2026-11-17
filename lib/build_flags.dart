const bool kEnableSelfUpdater = bool.fromEnvironment(
  'ENABLE_SELF_UPDATER',
  defaultValue: false,
);

const bool kUseNativeMediaPicker = bool.fromEnvironment(
  'USE_NATIVE_MEDIA_PICKER',
  defaultValue: false,
);

/// Hides the Unsplash photographer credit. Off by default, because Unsplash's API terms require
/// the credit; personal builds can turn it on with --dart-define-from-file=dart_defines.local.json.
const bool kHideUnsplashCredit = bool.fromEnvironment(
  'HIDE_UNSPLASH_CREDIT',
  defaultValue: false,
);
