
class ApiConfig {
  static const String baseUrl =
      'https://api.currentsapi.services/v1';

  static const String _envApiKey =
      String.fromEnvironment('uTPEoAa1-dUOEJVArhbhpuEhdJqZ8gs3v0CxMpgiebtgtchM');

  static const String fallbackApiKey ='uTPEoAa1-dUOEJVArhbhpuEhdJqZ8gs3v0CxMpgiebtgtchM';

  static String get apiKey =>
      _envApiKey.isNotEmpty ? _envApiKey : fallbackApiKey;

  static bool get hasApiKey =>
      apiKey.trim().isNotEmpty;
}
