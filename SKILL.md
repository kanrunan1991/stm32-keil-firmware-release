---
name: keil-firmware-release
description: 为 STM32 的 Keil MDK 工程发布 HEX 固件，更新版本记录、调用 UV4 编译、复制校验 Project 目录下的 HEX，并可按指定文件提交和推送到工程配置的 Git 远端。用于 STM32 固件发版或生成发布 HEX。
---

# STM32 Keil HEX 固件发版

使用本技能目录中的 [scripts/release.ps1](scripts/release.ps1)。安装、参数和示例见 [README.md](README.md)。支持单 Target 的 STM32 `.uvprojx` 工程；目标芯片、编译工具和支持包由实际工程配置决定。

## 发版前

- 从用户请求或工程记录确定版本号和改动说明，缺失时询问。日期默认当天，记录人默认 `Maintainer`，可由用户通过 `-Author` 指定。
- 检查工程根目录的 `README.md`、现有版本、`git status --short` 和 Keil 配置。保留用户的未提交改动和无关产物。
- 脚本默认在工程根目录 `Project` 下递归查找唯一 `.uvprojx`；多个工程文件时用 `-ProjectFile` 指定。只支持一个 Target，Device 必须以 STM32 开头。
- 确认 Keil 的 Output 已开启 Create HEX File。默认从 `OutputDirectory` 和 `OutputName` 推导 HEX；特殊布局用 `-BuiltFile` 指定相对于工程根目录的路径。工程文件和 HEX 都必须位于 `Project` 内。
- 检查 README 编码：需要 ASCII 兼容编码，推荐 UTF-8；不接受 UTF-16，不重写历史记录或修复历史乱码。
- 先执行 `-DryRun`，核对芯片、HEX 来源和发布文件名。预演不编译、不检查产物新旧、不验证编译工具可用性。实际编译前确认没有冲突的 Keil 构建。

## 生成发布文件

在本技能目录中执行，工程路径由实际任务提供：

```powershell
$releaseScript = Join-Path (Get-Location) 'scripts/release.ps1'
$firmwareRepo = Read-Host 'STM32 工程根目录'
$uv4Executable = Read-Host 'UV4.exe 的实际路径'
& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' -Description '修复启动初始化问题' -DryRun
& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' -Description '修复启动初始化问题' -UV4Path $uv4Executable
```

UV4 也可通过 `UV4_PATH` 环境变量或 PATH 提供。若执行策略阻止运行脚本，可在当前会话执行 `Set-ExecutionPolicy -Scope Process Bypass -Force` 后重试。

实际发版会重新构建工程，检查 HEX 存在、非空且本次已刷新，然后插入版本记录，将 HEX 复制到工程根目录并比较 SHA-256。默认输出 `<HEX原名>_v<版本>_<日期>.hex`；已有版本或同名文件时停止。

## 提交和推送

用户要求提交或推送时，核对本次文件和当前分支上游后，在实际发版命令中传入 `-Commit`、`-Push` 以及 `-CommitPaths`。仅生成文件的任务不默认提交或推送。

- `-Commit` 暂存工程 README、发布 HEX 和指定路径；已有暂存内容时停止。其他源码和被跟踪的原始 HEX，只有需要发布时才显式列入。
- `-Push` 必须与 `-Commit` 同用，目标来自当前分支的远端及上游配置，不猜测目标，不保存认证信息。
- 推送失败保留本地提交，解决问题后推送已有提交，不重复发版。发生其他失败时先检查 README、产物和暂存区，脚本没有自动回滚。

## 完成核对

- 检查 UV4 退出码、日志、HEX 时间及大小、复制前后的 SHA-256。脚本不验证 HEX 的地址布局或上板运行结果。
- 检查版本记录和历史内容，以及 `git diff --check`、`git status --short`。
- 若提交，检查提交只含本次文件；若推送，核对远端分支指向本次提交。
- `-SkipBuild` 仅用于已核实的现有 HEX：不检查本次刷新时间，不能证明与当前源码一致，向用户明确说明。

本技能不执行设备烧录、BIN 合并或工程清理，不自动改动源码版本号和 Keil 配置。
