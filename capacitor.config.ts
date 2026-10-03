import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.kasira.pos",
  appName: "KASIRA",
  webDir: "dist",
  bundledWebRuntime: false,
  server: { androidScheme: "https" },
  loggingBehavior: "none",
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
