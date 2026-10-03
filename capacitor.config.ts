import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.kasira.pos",
  appName: "KASIRA",
  webDir: "dist",
  bundledWebRuntime: false,
  server: { androidScheme: "https" }
};

export default config;
