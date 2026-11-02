import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.kasira.pos.offline",
  appName: "KASIRA Offline",
  webDir: "dist",
  bundledWebRuntime: false,
  server: { androidScheme: "https" },
  loggingBehavior: "none"
};

export default config;
