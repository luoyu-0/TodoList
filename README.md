# TodoList

一款面向 Windows 11 与 Android 的轻量 TodoList，采用本地优先（Offline-first）设计，支持离线使用、邮箱账号云同步和多设备共享。

## 当前状态

项目处于产品与技术方案阶段，暂未开始编写业务代码。方案与启动说明见 [docs](./docs/)。

## 默认技术方案

- 客户端：Flutter + Dart，一套 UI 代码覆盖 Windows 与 Android。
- 本地数据：SQLite + Drift，作为离线读写和同步队列。
- 云端：MySQL + 轻量 REST API；不引入复杂云端业务逻辑。
- 使用方式：只需构建可安装的 Android APK 与 Windows 桌面程序，不考虑应用商店发布。

这是可调整的初稿，正式开发前请确认 [docs/00-待确认决策.md](./docs/00-待确认决策.md)。

## 开发启动

需要 Windows 11、Flutter stable、Dart、Android Studio/Android SDK、Visual Studio 2022（安装“使用 C++ 的桌面开发”组件）、Git，以及可访问的 MySQL 和 REST API 服务。

代码骨架建立后，常用命令：

~~~powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run -d android
~~~

游客模式只保存本地数据，不创建云端数据；邮箱注册并登录后才启用云端同步和共享。

后端位于 [server](./server/)。安装依赖并启动开发服务：

~~~powershell
cd server
npm install
npm run prisma:generate
npm run dev
~~~

健康检查地址：GET http://127.0.0.1:3000/health。

## 文档目录

- [00-待确认决策](./docs/00-待确认决策.md)：需要确认的范围与风险。
- [01-产品需求与业务流程](./docs/01-产品需求与业务流程.md)：MVP、角色、页面和流程。
- [02-技术架构与工程规范](./docs/02-技术架构与工程规范.md)：客户端、云端、目录和质量门禁。
- [03-数据模型与同步协议](./docs/03-数据模型与同步协议.md)：数据表、游标、冲突和删除策略。
- [04-接口与安全设计](./docs/04-接口与安全设计.md)：认证、权限、接口和安全。
- [05-开发里程碑与验收标准](./docs/05-开发里程碑与验收标准.md)：阶段计划和验收条件。
- [06-开发启动与部署](./docs/06-开发启动与部署.md)：环境、测试、发布和回滚。

## 许可证

待项目负责人确认。
