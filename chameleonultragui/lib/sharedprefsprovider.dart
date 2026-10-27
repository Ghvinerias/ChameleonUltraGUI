import 'dart:convert';
import 'package:chameleonultragui/core/stores/prefs_card_store.dart';
import 'package:chameleonultragui/core/stores/prefs_dictionary_store.dart';
import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/models/card_folder.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:chameleonultragui/models/dictionary.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

export 'package:chameleonultragui/models/card_folder.dart';
export 'package:chameleonultragui/models/card_save.dart';
export 'package:chameleonultragui/models/dictionary.dart';

class SharedPreferencesProvider extends ChangeNotifier {
  SharedPreferencesProvider._privateConstructor();

  static final SharedPreferencesProvider _instance =
      SharedPreferencesProvider._privateConstructor();

  factory SharedPreferencesProvider() {
    return _instance;
  }

  late SharedPreferences _sharedPreferences;

  Future<void> load() async {
    _sharedPreferences = await SharedPreferences.getInstance();
    _cardStore = PrefsCardStore(_sharedPreferences)..pruneExpired();
    _dictionaryStore = PrefsDictionaryStore(_sharedPreferences)
      ..pruneExpired();
  }

  late PrefsCardStore _cardStore;
  late PrefsDictionaryStore _dictionaryStore;

  /// Stores own all stamping/tombstoning of cards, dictionaries and folders;
  /// the legacy get/set methods below delegate to them.
  PrefsCardStore get cardStore => _cardStore;
  PrefsDictionaryStore get dictionaryStore => _dictionaryStore;

  ThemeMode getTheme() {
    final themeValue = _sharedPreferences.getInt('app_theme') ?? 0;
    return ThemeMode.values[themeValue];
  }

  void setTheme(ThemeMode theme) {
    _sharedPreferences.setInt('app_theme', theme.index);
  }

  bool getSideBarAutoExpansion() {
    return _sharedPreferences.getBool('sidebar_auto_expanded') ?? true;
  }

  bool getSideBarExpanded() {
    return _sharedPreferences.getBool('sidebar_expanded') ?? false;
  }

  int getSideBarExpandedIndex() {
    return _sharedPreferences.getInt('sidebar_expanded_index') ?? 1;
  }

  void setSideBarAutoExpansion(bool autoExpanded) {
    _sharedPreferences.setBool('sidebar_auto_expanded', autoExpanded);
  }

  void setSideBarExpanded(bool expanded) {
    _sharedPreferences.setBool('sidebar_expanded', expanded);
  }

  void setSideBarExpandedIndex(int index) {
    _sharedPreferences.setInt('sidebar_expanded_index', index);
  }

  int getThemeColorIndex() {
    return _sharedPreferences.getInt('app_theme_color') ?? 0;
  }

  MaterialColor getThemeColor() {
    return colors.getThemeColor(getThemeColorIndex());
  }

  Color getThemeComplementaryColor() {
    final themeMode = _sharedPreferences.getInt('app_theme') ?? 2;
    return colors.getThemeComplementary(themeMode, getThemeColorIndex());
  }

  void setThemeColor(int color) {
    _sharedPreferences.setInt('app_theme_color', color);
  }

  bool isDebugMode() {
    return _sharedPreferences.getBool('debug') ?? false;
  }

  void setDebugMode(bool value) {
    _sharedPreferences.setBool('debug', value);
  }

  bool isEmulatedChameleon() {
    return _sharedPreferences.getBool('emulate_device') ?? false;
  }

  void setEmulatedChameleon(bool value) {
    _sharedPreferences.setBool('emulate_device', value);
  }

  List<Dictionary> getDictionaries({int keyLength = 0}) =>
      _dictionaryStore.getDictionariesSync(keyLength: keyLength);

  /// Bulk replace; diffed by the store (stamps changed items, tombstones
  /// removed ones). The system empty dictionary (id "") is never saved.
  void setDictionaries(List<Dictionary> dictionaries) =>
      _dictionaryStore.replaceDictionaries(dictionaries);

  List<DictionaryFolder> getDictionaryFolders() =>
      _dictionaryStore.getFoldersSync();

  void setDictionaryFolders(List<DictionaryFolder> folders) =>
      _dictionaryStore.replaceFolders(folders);

  List<CardSave> getCards() => _cardStore.getCardsSync();

  void setCards(List<CardSave> cards) => _cardStore.replaceCards(cards);

  List<CardFolder> getCardFolders() => _cardStore.getFoldersSync();

  void setCardFolders(List<CardFolder> folders) =>
      _cardStore.replaceFolders(folders);

  void setLocale(Locale loc) {
    for (var locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() ==
          loc.toLanguageTag().toLowerCase()) {
        _sharedPreferences.setString('locale', loc.toLanguageTag());
        notifyListeners();
        return;
      }
    }
  }

  String getLocaleString() {
    return _sharedPreferences.getString("locale") ?? "en";
  }

  Locale getLocale() {
    final localeId = getLocaleString();
    Locale locale;
    if (localeId.contains("-")) {
      final [lcode, ccode] = localeId.toString().split("-");
      locale = Locale(lcode, ccode);
    } else {
      locale = Locale(localeId);
    }
    if (!AppLocalizations.supportedLocales.contains(locale)) {
      return const Locale('en');
    } else {
      return locale;
    }
  }

  void clearLocale() {
    _sharedPreferences.setString('locale', "en");
    notifyListeners();
  }

  bool isDebugLogging() {
    return _sharedPreferences.getBool('debug_logging') ?? false;
  }

  void setDebugLogging(bool value) {
    _sharedPreferences.setBool('debug_logging', value);
  }

  void addLogLine(String value) {
    List<String> rows =
        _sharedPreferences.getStringList('debug_logging_value') ?? [];
    rows.add(value);

    if (rows.length > 5000) {
      rows.removeAt(0);
    }

    _sharedPreferences.setStringList('debug_logging_value', rows);
  }

  void clearLogLines() {
    _sharedPreferences.setStringList('debug_logging_value', []);
  }

  List<String> getLogLines() {
    return _sharedPreferences.getStringList('debug_logging_value') ?? [];
  }

  String dumpSettingsToJson() {
    Map<String, dynamic> settingsMap = {};

    for (var key in _sharedPreferences.getKeys()) {
      if (key == "debug_logging_value") {
        continue;
      }
      var value = _sharedPreferences.get(key) as dynamic;
      if (value == null) {
        continue;
      }
      if (value is List) {
        // this hack is needed in order to output proper json with objects instead of objects-in-strings
        value = value.map((e) => jsonDecode(e)).toList();
      }
      settingsMap[key] = value;
    }

    return jsonEncode(settingsMap);
  }

  void restoreSettingsFromJson(String jsonSettings) {
    Map<String, dynamic> settingsMap = jsonDecode(jsonSettings);

    for (var key in settingsMap.keys) {
      dynamic value = settingsMap[key];

      if (value == null) {
        continue;
      }
      switch (value) {
        case String s:
          _sharedPreferences.setString(key, s);
          break;
        case int i:
          _sharedPreferences.setInt(key, i);
          break;
        case double d:
          _sharedPreferences.setDouble(key, d);
          break;
        case bool b:
          _sharedPreferences.setBool(key, b);
          break;
        case List l:
          // this is the reverse of the hack above :)
          _sharedPreferences.setStringList(
              key, l.map((e) => jsonEncode(e)).toList());
          break;
        default:
          break;
      }
    }
  }

  bool getConfirmDelete() {
    return _sharedPreferences.getBool('confirm_delete') ?? true;
  }

  void setConfirmDelete(bool value) {
    _sharedPreferences.setBool('confirm_delete', value);
  }

  bool getAutoScanEnabled() {
    return _sharedPreferences.getBool('auto_scan_enabled') ?? true;
  }

  void setAutoScanEnabled(bool value) {
    _sharedPreferences.setBool('auto_scan_enabled', value);
  }

  bool getAutoConnectFirstFoundDevice() {
    return _sharedPreferences.getBool('auto_connect_first_found') ?? false;
  }

  void setAutoConnectFirstFoundDevice(bool value) {
    _sharedPreferences.setBool('auto_connect_first_found', value);
  }
}
