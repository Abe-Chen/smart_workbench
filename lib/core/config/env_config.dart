import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EnvConfig {
  const EnvConfig({
    required this.volcArkApiKey,
    required this.doubaoEndpointId,
    required this.xfAppId,
    required this.xfApiKey,
    required this.xfApiSecret,
    required this.amapKey,
  });

  factory EnvConfig.fromDotEnv() {
    String read(String key) => dotenv.env[key]?.trim() ?? '';
    return EnvConfig(
      volcArkApiKey: read('VOLC_ARK_API_KEY'),
      doubaoEndpointId: read('DOUBAO_ENDPOINT_ID'),
      xfAppId: read('XF_APP_ID'),
      xfApiKey: read('XF_API_KEY'),
      xfApiSecret: read('XF_API_SECRET'),
      amapKey: read('AMAP_KEY'),
    );
  }

  final String volcArkApiKey;
  final String doubaoEndpointId;
  final String xfAppId;
  final String xfApiKey;
  final String xfApiSecret;
  final String amapKey;

  bool get hasDoubaoCredentials =>
      volcArkApiKey.isNotEmpty && doubaoEndpointId.isNotEmpty;

  bool get hasXunfeiCredentials =>
      xfAppId.isNotEmpty && xfApiKey.isNotEmpty && xfApiSecret.isNotEmpty;

  bool get hasAmapCredentials => amapKey.isNotEmpty;
}

final Provider<EnvConfig> envConfigProvider = Provider<EnvConfig>(
  (Ref ref) => EnvConfig.fromDotEnv(),
);
