import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.vora.ecosystem",
  appName: "VORA",
  webDir: "dist",
  bundledWebRuntime: false,
  server: { androidScheme: "https" },
  loggingBehavior: "none",
  buildOptions: {
    keystorePath: process.env.VORA_KEYSTORE_PATH || process.env.KASIRA_KEYSTORE_PATH,
    keystorePassword: process.env.VORA_KEYSTORE_PASSWORD || process.env.KASIRA_KEYSTORE_PASSWORD,
    keystoreAlias: process.env.VORA_KEYSTORE_ALIAS || process.env.KASIRA_KEYSTORE_ALIAS,
    keystoreAliasPassword: process.env.VORA_KEYSTORE_ALIAS_PASSWORD || process.env.KASIRA_KEYSTORE_ALIAS_PASSWORD,
    releaseType: "AAB",
    signingType: "jarsigner"
  }
};

export default config;
