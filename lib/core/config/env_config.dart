class EnvConfig {
  static String get freeraspReleaseHash =>
      const String.fromEnvironment('FREERASP_RELEASE_HASH');

  static String get freeraspPackageName =>
      const String.fromEnvironment('FREERASP_PACKAGE_NAME');

  static String get wiredashProjectId =>
      const String.fromEnvironment('WIREDASH_PROJECT_ID');

  static String get wiredashApiSecret =>
      const String.fromEnvironment('WIREDASH_API_SECRET');
}
