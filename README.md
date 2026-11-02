# ESP_BC — 盛和养老智能床垫 ESP32 板端固件（AWS IoT Core 版）

ESP32 主控固件，用于盛和养老智能床垫 BC 模块：连接 SU2 睡眠传感器、MFP 床控主控盒，经 WiFi / 蓝牙与 **AWS IoT Core（中国区）** 云端通信，实现实时数据上报、睡眠报告、OTA 升级、床控与打鼾干预等功能。

> **平台迁移说明**：自 V2.4.0 起，MQTT 已从涂鸦 IoT（阿里云版）整体切换至 **AWS IoT Core**，设备通过 X.509 双向 TLS（mTLS）认证接入；OTA HTTPS 下载校验也改用内置 Amazon 根证书。历史涂鸦/阿里云代码仅作兼容保留。

**当前版本：** `BC_ESP_2026_2_4_0`（V2.4.0）  
**芯片：** ESP32  
**工程名：** `bochang-program`  
**云端：** AWS IoT Core（`cn-north-1` 中国（北京）区）

---

## 主要功能

| 模块 | 说明 |
|------|------|
| **WiFi** | STA 模式，支持断线重连；获 IP 后 SNTP 对时，再建立 MQTT |
| **蓝牙 BLE** | 配网、数据透传、床控指令下发 |
| **AWS MQTT** | `mqtts://<endpoint>:8883`，X.509 双向 TLS 认证（无用户名密码），keepalive 300s，连上即上报板端/传感器版本 |
| **传感器 SU2** | UART1 与 SU2 模块通信，解析 5s / 60s / 睡眠报告 / 呼吸暂停等 protobuf 数据；支持云端传感器 OTA |
| **MFP 床控** | UART2 与主控盒通信，支持 MQTT / BLE 床控、打鼾干预、闹钟联动 |
| **OTA** | HTTPS 双分区升级，内置 Amazon 根证书校验，MQTT 下行升级指令，上线 inform 版本、进度上报 |
| **数据上报** | 5s（type:1）、60s（type:2）、睡眠报告、呼吸暂停、气袋、打鼾参数等 JSON 经 MQTT / BLE 上报 |

---

## 开发环境

| 项目 | 要求 |
|------|------|
| 芯片 | ESP32 |
| 框架 | [ESP-IDF](https://docs.espressif.com/projects/esp-idf/) v4.4.x（与现有 `sdkconfig` 匹配） |
| 工具 | VS Code + Espressif IDF 插件，或 IDF 命令行 |
| 操作系统 | Windows / Linux / macOS |

### 构建与烧录

```bash
idf.py set-target esp32
idf.py build
idf.py -p COMx flash monitor
```

也可在 VS Code 底部 IDF 面板中选择 **Build / Flash / Monitor**。

### 菜单配置

```bash
idf.py menuconfig
```

分区表使用根目录 [`my_partitions.csv`](my_partitions.csv)（含 `ota_0` / `ota_1` 双应用分区、`storage` 8M FAT、`nvs_certs` 32K 证书分区）。

---

## AWS IoT Core 接入说明（重点）

设备通过 **X.509 证书双向 TLS** 接入 AWS IoT Core，不再使用三元组（ProductKey / DeviceName / DeviceSecret）密码认证。

| 项目 | 值 |
|------|------|
| Endpoint | `airykrld1d7awu3.ats.iot.cn-north-1.amazonaws.com.cn` |
| 端口 | `8883`（mqtts） |
| Client ID | 设备 ID（如 `KSPSBED00010008`） |
| 认证方式 | mTLS：Root CA + 设备证书 + 设备私钥，**无用户名密码** |

### 证书存放与烧录

证书**不编译进固件**，而是运行时从 flash 的 `nvs_certs` 分区（NVS 格式，32KB）读取，量产换设备只需烧录对应证书分区，固件无需重编。

证书文件放在 `components/use_wifi/certs/`（已被 `.gitignore` 排除，**永不入库**）：

```
components/use_wifi/certs/
├── AmazonRootCA1.pem              # AWS 根 CA
├── <DeviceId>.cert.pem            # 设备证书（AWS IoT 控制台创建物证书后下载）
└── <DeviceId>.private.key         # 设备私钥
```

使用根目录 [`make_certs_bin.ps1`](make_certs_bin.ps1) 一键打包并烧录（Windows PowerShell）：

```powershell
# 仅生成 nvs_certs_<DeviceId>.bin
.\make_certs_bin.ps1 -DeviceId KSPSBED00010008

# 生成并直接烧录到设备 nvs_certs 分区
.\make_certs_bin.ps1 -DeviceId KSPSBED00010008 -Flash -Port COM3
```

脚本内部调用 ESP-IDF 的 `nvs_partition_gen.py` 生成 bin，再用 `parttool.py` 按分区名（`nvs_certs`）自动定位偏移烧录——分区表调整后无需改脚本。

> ⚠️ 私钥仅存在于本地 certs 目录与设备 `nvs_certs` 分区，严禁提交到 Git 或随固件分发。

---

## 工程目录结构

```
ESP_BC/
├── main/
│   └── main.c                      # 入口：NVS、BLE、WiFi、MFP、app_control
├── components/
│   ├── common/                     # 全局配置、设备信息、NVS
│   ├── app_control/                # 业务主控：SU2 解析、上报、床控、打鼾干预
│   ├── use_wifi/                   # WiFi、SNTP、AWS MQTT、OTA、证书加载
│   │   └── certs/                  # 设备证书（gitignore，本地放置）
│   ├── use_ble_server/             # BLE GATT 服务
│   ├── use_uart/                   # UART 驱动封装
│   ├── use_mfp/                    # MFP 床控协议
│   ├── use_adc/                    # ADC / CH423（按需）
│   ├── use_pwm/                    # PWM（按需）
│   └── protobuf/                   # SU2 protobuf 编解码
├── make_certs_bin.ps1              # AWS 证书打包/烧录脚本
├── my_partitions.csv               # 自定义分区表（含 nvs_certs）
├── sdkconfig / sdkconfig.defaults
└── docs/                           # 架构与协议文档
```

---

## 硬件接口（默认引脚）

| 接口 | 引脚 | 用途 |
|------|------|------|
| UART1 TX / RX | GPIO 22 / 26 | SU2 睡眠传感器 |
| UART2 TX / RX | GPIO 19 / 25 | MFP 主控盒 |
| LED | GPIO 19 / 18 / 5 | 蓝 / 绿 / 红 |

具体以 [`components/common/common.h`](components/common/common.h) 中宏定义为准。

---

## 配置说明

关键编译宏位于 [`components/common/common.h`](components/common/common.h)：

| 宏 | 说明 |
|----|------|
| `INIT_VERSION` | 固件版本字符串（当前 `BC_ESP_2026_2_4_0`），OTA inform 与 NVS 使用 |
| `DEVEICE_ID` | 默认设备 ID（如 `KSPSBED00010008`），AWS MQTT Client ID 与上报 JSON 中的 `id` 使用 |
| `OTA_ON_OFF` | OTA 功能开关 |
| `DATA_UP` | 数据上报总开关 |
| `ALIYUN_BURN` | 历史涂鸦/阿里云三元组开关（AWS 模式下不使用，仅兼容保留） |

默认 WiFi SSID / 密码也在 `common.h` 中，量产前请改为现场网络或通过 BLE 配网写入 NVS。

---

## 云端 MQTT Topic（AWS 模式）

AWS 模式下 Topic 以设备 ID 为前缀（无 ProductKey），连接成功后订阅 / 发布：

| 方向 | Topic | 说明 |
|------|-------|------|
| 发布 | `{deviceId}/user/5s/put` | 5s 实时数据 |
| 发布 | `{deviceId}/user/60s/put` | 60s 统计数据 |
| 发布 | `{deviceId}/user/sleep/put` | 睡眠报告 |
| 发布 | `{deviceId}/user/sa/put` | 呼吸暂停数据 |
| 发布 | `{deviceId}/user/airbag/put` | 气袋数据 |
| 订阅 | `{deviceId}/user/cli/get` | CLI 指令（sensorCli / deviceCli / mcCli） |
| 发布 | `{deviceId}/user/cli/put` | CLI 应答 |
| 发布 | `{deviceId}/user/mccli/put` | MFP 床控应答 |
| 订阅 | `{deviceId}/ota/upgrade/get` | OTA 升级下行 |
| 发布 | `{deviceId}/ota/inform/put` | OTA 版本 inform（每次连上 MQTT 上报，含板端/传感器版本） |
| 发布 | `{deviceId}/ota/progress/put` | OTA 进度上报 |

### 5s / 60s 数据格式

`ts` 为 ESP 上报时刻，`sensor_ts` 为传感器侧采样时间戳：

```json
{
  "id": "KSPSBED00010008",
  "ts": 1710000000,
  "type": 1,
  "data": {
    "sensor_ts": 1709999995,
    "heart": 72,
    "breath": 16,
    "status": [0, 0, 0, 0, 0]
  }
}
```

### OTA 升级下行示例

```json
{
  "params": {
    "version": "BC_ESP_2026_2_4_0",
    "url": "https://example.com/firmware.bin"
  }
}
```

`data` 与 `params` 字段均可，需包含 `version`、`url`；HTTPS 下载使用内置 Amazon 根证书校验服务器。

---

## 烧录清单

一台全新设备完整烧录顺序（以 `idf.py` / `esptool` 为例）：

1. **固件四件套**：`bootloader.bin`、`partition-table.bin`（`my_partitions.csv` 生成）、`bochang-program.bin`、`ota_data_initial.bin`
2. **AWS 证书分区**：`.\make_certs_bin.ps1 -DeviceId <设备ID> -Flash`（写入 `nvs_certs`）
3. 如需产测三元组（历史涂鸦兼容），另行写入 `storage` 分区

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [`docs/SU2_通信架构.md`](docs/SU2_通信架构.md) | SU2 通信架构设计 |
| [`docs/盛和养老系统下发协议V2.5.docx`](docs/盛和养老系统下发协议V2.5.docx) | 云端 / APP 下发协议 |
| [`docs/智能床通信协议20250416.docx`](docs/智能床通信协议20250416.docx) | 智能床通信协议 |

---

## 近期版本演进

| 版本 | 说明 |
|------|------|
| V2.4.0 | **MQTT 从涂鸦（阿里云）切换到 AWS IoT Core**（mTLS 证书认证）；OTA HTTPS 校验改用内置证书束；MQTT 连上即上报板端/传感器版本；证书改为 `nvs_certs` 分区运行时加载；新增证书打包烧录脚本 |
| V2.3.5 | 云端传感器 OTA；删除 BLE SU2 升级 |
| V2.3.4 | 涂鸦 log 打印兼容（迁移前末版） |

---

## 许可证

内部项目，版权归 KEESON / 盛和相关团队所有。未经授权请勿对外分发固件、设备证书与私钥。
