import type { CapacitorConfig } from "@capacitor/cli";

const offlineMode = process.env.KASIRA_OFFLINE === "1";

const config: CapacitorConfig = {
  appId: offlineMode ? "com.kasira.pos.offline" : "com.kasira.pos",
  appName: offlineMode ? "KASIRA Offline" : "KASIRA",
  webDir: "dist",
  bundledWebRuntime: false,
  server: { androidScheme: "https" },
  loggingBehavior: "none",
  android: { path: offlineMode ? "android-offline" : "android" },
  buildOptions: {
    keystorePath: process.env.KASIRA_KEYSTORE_PATH,
    keystorePassword: process.env.KASIRA_KEYSTORE_PASSWORD,
    keystoreAlias: process.env.KASIRA_KEYSTORE_ALIAS,
    keystoreAliasPassword: process.env.KASIRA_KEYSTORE_ALIAS_PASSWORD,
    releaseType: "AAB",
    signingType: "jarsigner"
  }
};

export default config;
