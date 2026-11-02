# keil-firmware-release

为 **STM32 系列芯片的 Keil MDK 工程**准备 HEX 固件发布。通过 `SKILL.md` 提供 Codex 工作流程，通过 `scripts/release.ps1` 执行编译、版本记录、发布文件复制和校验，以及可选的 Git 提交和推送。

## 1. 解决什么问题

减少人工发版时遗漏版本记录、复制旧固件、命名不统一、误提交其他修改等问题。发布来源是目标工程 `Project` 目录下的 `.hex` 文件，输出为工程根目录下带版本和日期的 HEX 副本。

本工具按 Keil 配置中的 STM32 Device 识别工程，适用于工具链和芯片支持包已配置好的单 Target STM32 工程。它不替代芯片选型、编译器配置、设备烧录或上板验证，也不执行 BIN 转换和 Bootloader 合并。

## 2. 主要功能

| 功能 | 实际行为 |
| --- | --- |
| 识别工程 | 在 `Project` 下递归查找唯一 `.uvprojx`，也可显式指定；要求单 Target，Device 以 STM32 开头。 |
| 定位 HEX | 按 `OutputDirectory` 和 `OutputName` 推导来源；输出目录相对于 `.uvprojx` 所在目录。可用 `-BuiltFile` 指定其他 HEX，但仍须位于工程根目录的 `Project` 内。 |
| 预演 | 显示路径、芯片和版本信息，检查命名及配置；不修改文件、不编译、不提交、不推送。 |
| 重新构建 | 调用 `UV4.exe -r <工程> -j0 -o <日志>`；退出码 0 或 1 时继续，为空或大于等于 2 时停止。 |
| 更新版本记录 | 在工程 README 的首个 `## v数字` 标题前插入版本、日期、记录人和编号改动说明，保留历史字节及原换行风格。 |
| 复制和校验 | 检查来源 HEX 存在、非空；编译模式检查修改时间已刷新，容许两秒误差。复制到工程根目录并比较 SHA-256。 |
| 可选提交推送 | 只暂存 README、发布 HEX 和指定路径，推送至当前分支配置的上游远端分支。 |

典型工程布局（文件名仅为示例）：

```text
firmware/
├── README.md
├── Project/
│   ├── Firmware.uvprojx
│   └── Objects/
│       └── Firmware.hex          # Keil 生成的发布来源
└── Firmware_v1.0.0_20261102.hex   # 脚本复制出的发布副本
```

在 Keil **Options for Target → Output** 中开启 **Create HEX File**，并确认输出目录位于 `Project` 内。该选项的行为见 [Keil 官方 Output 说明](https://www.keil.com/support/man/docs/uv4/uv4_dg_adsout.asp)。脚本读取配置，不自动替你修改工程。

## 3. 安装方法

### 环境要求

- Windows PowerShell 5.1 或 PowerShell 7，以及工程目录读写权限。
- 实际编译需要 Keil MDK、所用 STM32 对应的支持包和工程配置的编译工具。
- 工程根目录包含 `Project`，其下包含所用 `.uvprojx` 和 HEX 输出位置。多个工程文件需指定 `-ProjectFile`；多 Target 工程需要先人工选择或整理成单 Target 工程。
- 工程根目录已有 `README.md`，至少包含一个 `## v0.9.0` 形式的历史版本标题。推荐 UTF-8，支持 ASCII 兼容编码，不支持 UTF-16。
- 提交和推送需要 Git；推送还需配置上游分支和本机凭据。

### 安装为 Codex 技能

本包包含 `SKILL.md`、`README.md`、`LICENSE`、`.gitignore` 和 `scripts/release.ps1`。

先在 PowerShell 中进入本技能包目录，再执行以下命令，将整个包安装至当前用户的 `.codex/skills`。`$HOME` 表示运行者的用户目录，不绑定某台机器：

```powershell
$skillPackage = (Get-Location).Path
$skillInstallParent = Join-Path $HOME '.codex/skills'
$skillInstallDir = Join-Path $skillInstallParent 'keil-firmware-release'
if (Test-Path -LiteralPath $skillInstallDir) {
    throw '技能已存在；可跳过安装。更新前请备份并核对原目录。'
}
New-Item -ItemType Directory -Path $skillInstallParent -Force | Out-Null
Copy-Item -LiteralPath $skillPackage -Destination $skillInstallDir -Recurse
```

安装后确认用户技能目录下的 `keil-firmware-release/SKILL.md` 和 `scripts/release.ps1` 存在，再在 Codex 中明确引用该技能。也可直接运行包内脚本，无需安装为技能。

## 4. 使用方法

### 基本发版：先预演，再构建

在本技能目录中打开 PowerShell，填写实际工程根目录和 UV4 路径：

```powershell
$releaseScript = Join-Path (Get-Location) 'scripts/release.ps1'
$firmwareRepo = Read-Host 'STM32 工程根目录'
$uv4Executable = Read-Host 'UV4.exe 的实际路径'

& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' `
    -Description '修复启动初始化问题' -DryRun

# 核对预演输出，并确认没有其他 Keil 构建正在进行。
& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' `
    -Description '修复启动初始化问题' -UV4Path $uv4Executable
```

实际构建时 UV4 的查找顺序为 `-UV4Path`、环境变量 `UV4_PATH`、PATH 中的 `UV4.exe`。预演不要求安装 Keil，也不验证编译工具、HEX 是否存在或是否最新。实际发版不验证 HEX 内容是否适合烧录到目标硬件。

若 PowerShell 的执行策略阻止脚本，可仅对当前会话执行 `Set-ExecutionPolicy -Scope Process Bypass -Force` 后重试。

### 显式选择工程和 HEX

以下路径均相对于目标工程根目录，文件名按实际工程替换：

```powershell
& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' `
    -Description '修复启动初始化问题' `
    -ProjectFile 'Project/Firmware.uvprojx' `
    -BuiltFile 'Project/Objects/Firmware.hex' -DryRun
```

### 可选提交和推送

需要提交和推送时，用以下命令**替代**基本发版的实际执行命令。不要对已经成功发布的同一版本重新发版：

```powershell
& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' `
    -Description '修复启动初始化问题' -UV4Path $uv4Executable `
    -Commit -Push -CommitPaths @('Core/Src/main.c')
```

只提交时使用 `-Commit`；只生成文件时不传这两个开关。`-CommitPaths` 仅列入本次需要提交的实际文件。若原始 HEX 已被 Git 跟踪且需要提交，应显式加入该路径。暂存区原本非空时停止。

在 Codex 中也可直接说明：

```text
使用 keil-firmware-release 为当前 STM32 工程发布 1.0.0。
改动：修复启动初始化问题。
先预演，再编译并复制 Project 下的 HEX；本次不提交、不推送。
```

### 参数说明

| 参数 | 默认值 / 要求 | 说明 |
| --- | --- | --- |
| `-RepoPath` | `.` | 目标 STM32 工程根目录。 |
| `-Version` | 必填 | 数字及点分隔的版本，如 `1.0.0`，不含前缀 `v`。 |
| `-Description` | 必填 | 改动说明；多行内容生成编号条目。 |
| `-Author` | `Maintainer` | 版本记录人，可显式传入团队名称。 |
| `-Date` | 当天 | 有效的 `yyyyMMdd` 日期。 |
| `-ProjectFile` | 自动查找 | `Project` 下的 `.uvprojx`，支持工程相对路径或绝对路径。 |
| `-BuiltFile` | 从工程配置推导 | `Project` 下的 `.hex`，支持工程相对路径或绝对路径。 |
| `-UV4Path` | 自动查找 | 实际 UV4 程序路径；还可通过 `UV4_PATH` 或 PATH 配置。 |
| `-ReleaseName` | `<HEX原名>_v<版本>_<日期>.hex` | 单个 `.hex` 文件名，不带目录。 |
| `-SkipBuild` | 关闭 | 使用已核实的现有 HEX，跳过编译和刷新时间检查。 |
| `-Commit` | 关闭 | 暂存指定文件并提交。 |
| `-Push` | 关闭 | 必须同时指定 `-Commit`，推送至配置的上游。 |
| `-CommitPaths` | 空数组 | 除工程 README 和发布 HEX 外，需要提交的文件。 |
| `-DryRun` | 关闭 | 仅预演，不执行发版动作。 |

## 5. 输入输出示例

以下为示意，不代表已经完成真实硬件工程构建。假设 `Firmware.uvprojx` 的 Device 是 `STM32F103C8`，OutputDirectory 是 `./Objects/`，OutputName 是 `Firmware`，CreateHexFile 为 `1`，且版本和发布文件尚不存在。

输入（延用前文变量）：

```powershell
$releaseDescription = "修复启动初始化问题`n调整串口超时处理"
& $releaseScript -RepoPath $firmwareRepo -Version '1.0.0' `
    -Description $releaseDescription -Date '20261102' -DryRun
```

预演输出（`<工程根目录>` 为占位说明，脚本运行时显示实际路径）：

```text
Repo: <工程根目录>
Project: <工程根目录>/Project/Firmware.uvprojx
STM32 device: STM32F103C8
Built HEX: <工程根目录>/Project/Objects/Firmware.hex
Release HEX: <工程根目录>/Firmware_v1.0.0_20261102.hex
README entry: ## v1.0.0 20261102 Maintainer
Dry run: no files changed, no build, commit or push run.
```

提供 UV4 并去掉 `-DryRun`，实际发版成功后，在工程 README 的首个历史版本标题前插入：

```markdown
## v1.0.0 20261102 Maintainer
1. 修复启动初始化问题
2. 调整串口超时处理
```

工程根目录新增 `Firmware_v1.0.0_20261102.hex`，内容与来源 HEX 相同。控制台还会显示：

```text
UV4 exit code: 0; log: <系统临时目录>/keil_release_<时间戳>.log
HEX SHA-256: <实际64位十六进制摘要>
Release prepared.
```

指定提交推送开关后，还会输出 Git 操作结果；成功推送显示 `Pushed to <远端> refs/heads/<分支>`。构建过程中产生的其他文件由目标工程配置决定。

## 6. 停止条件与使用边界

- 重复版本、重复发布文件、README 缺失或无历史版本标题时停止，不覆盖已有发布文件。
- 非 STM32 Device、多 Target、无法唯一识别工程、HEX 路径不在 `Project` 内，或构建模式未开启 Create HEX File 时停止。
- 构建失败、HEX 不存在、为空或本次未刷新时停止。脚本不校验 Intel HEX 记录校验和、地址范围或硬件兼容性。
- `-SkipBuild` 仅适用于已人工核实的产物，不能证明现有 HEX 与源码一致；该模式允许工程当前未开启 Create HEX File。
- 推送前要求有效的当前分支、远端和上游配置。推送失败会保留本地提交，修复问题后推送已有提交，不重复发版。
- 没有失败自动回滚。部分步骤失败时，可能已留下 README 修改、发布文件或暂存内容，应先核对状态再继续。
- 不自动更改源码版本号，不烧录设备，不清理目标工程。

## 7. 公开内容与许可证

此技能包使用通用变量、相对示例路径和默认记录人 `Maintainer`，不需要在源码中保存个人目录、身份信息或认证凭据。Git 认证使用运行环境配置。运行日志保存在系统临时目录，提交信息临时文件在提交操作结束后清理；日志可能包含实际工程路径，分享前需按实际内容核对。

`.gitignore` 排除常见凭据文件、运行日志、缓存及固件构建产物，仅作用于本技能包所在仓库，不会改动目标固件仓库的规则，也不会移除已跟踪文件。公开前还应检查实际 Git 历史和新增文件。

本项目采用 [MIT License](LICENSE)。Keil、STM32 支持包和目标工程固件各自的许可不因本技能的许可证而改变。
