import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const windows = process.platform === "win32";
const npx = windows ? "npx.cmd" : "npx";
const env = { ...process.env, KASIRA_OFFLINE: "1" };

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    env,
    shell: windows,
    ...options
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

const androidDir = resolve("android-offline");
if (!existsSync(androidDir)) {
  run(npx, ["cap", "add", "android"]);
}
run(npx, ["cap", "sync", "android"]);

const gradle = resolve(androidDir, windows ? "gradlew.bat" : "gradlew");
if (!existsSync(gradle)) {
  throw new Error("Gradle wrapper KASIRA Offline tidak ditemukan di android-offline.");
}
run(gradle, ["assembleDebug", "--no-daemon"], { cwd: androidDir });
console.log("KASIRA Offline debug APK built in android-offline/app/build/outputs/apk/debug.");
