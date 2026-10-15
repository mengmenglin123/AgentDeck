# HuanHermes 原生安卓版（Kotlin + Jetpack Compose）

与 `apps/mobile`（Flutter）同 applicationId `com.huanmeng.huanhermes`、同签名，versionCode 从 2000 起，可直接覆盖安装 Flutter 版。

- 构建：`gradle :app:assembleRelease`（Gradle 8.11.1，JDK 17，Android SDK 35）
- CI：`.github/workflows/native-apk.yml`；推 `native-v<版本>-rc<N>` 标签会把 APK 发到本仓库的 prerelease
- 计划与里程碑：见 Hark 项目里的原生重写计划（M0–M6）
