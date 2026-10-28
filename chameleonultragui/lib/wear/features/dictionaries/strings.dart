/// English strings of the Dictionaries feature (no .arb entries by design).
class DictStrings {
  DictStrings._();

  static const title = 'Dictionaries';
  static const empty = 'No dictionaries on the watch yet.';
  static const syncHint = 'Sync with your phone to get your own dictionaries';
  static const download = 'Download';
  static const useAll = 'Use all';
  static const useForChecks = 'Use for key checks';
  static const notForChecks = 'Not used for key checks';
  static const delete = 'Delete';
  static const cancel = 'Cancel';
  static const done = 'Done';
  static const firstKeys = 'First keys';
  static const noKeys = 'No keys';
  static const deleteTitle = 'Delete dictionary?';
  static const deleteBuiltIn = 'Built-in, cannot be deleted';
  static const downloadTitle = 'Download';
  static const downloading = 'Downloading';
  static const cancelled = 'Cancelled';

  static String keyCount(int n) => n == 1 ? '1 key' : '$n keys';
  static String keyBytes(int hexLength) => '${hexLength ~/ 2}-byte';
  static String total(int keys) => '${keyCount(keys)} to try';
  static String estimate(String time) => '~$time';
  static const largeWarning =
      'Many keys: key checks will take a while. Turn some dictionaries off.';
  static String deleteMessage(String name) => 'Delete "$name"?';
  static String saved(String name, int keys) =>
      'Saved "$name" (${keyCount(keys)})';

  // Download failures.
  static const noNetwork = 'No network connection';
  static const timeout = 'The server took too long';
  static String httpError(int code) => 'Server error ($code)';
  static String tooLarge(int maxBytes) =>
      'File too large (max ${maxBytes ~/ (1024 * 1024)} MB)';
  static const malformed = 'No valid keys found in file';
  static const duplicate = 'Already on the watch';
  static const failed = 'Download failed';
}
