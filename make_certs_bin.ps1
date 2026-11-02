<#
.SYNOPSIS
    一键打包 AWS 设备证书为 NVS bin 文件
.EXAMPLE
    .\make_certs_bin.ps1 -DeviceId KSPSBED00009960
    .\make_certs_bin.ps1 -DeviceId KSPSBED00009960 -Flash   # 生成并直接烧录
.NOTES
    证书文件放在 components\use_wifi\certs\<DeviceId>.cert.pem 和 .private.key
    Root CA 固定为 AmazonRootCA1.pem
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$DeviceId,

    [switch]$Flash,

    [string]$Port = "COM3"
)

$ErrorActionPreference = "Stop"

# ==== 路径配置（按你本机实际情况改这里）====
$IDF_PATH       = "E:\esp\v4.4.8\frameworks\esp-idf-v4.4.8"
$IDF_PYTHON     = "E:\esp\v4.4.8\python_env\idf4.4_py3.11_env\Scripts\python.exe"
$NVS_TOOL       = Join-Path $IDF_PATH "components\nvs_flash\nvs_partition_generator\nvs_partition_gen.py"
$PARTTOOL       = Join-Path $IDF_PATH "components\partition_table\parttool.py"

# ==== 分区配置（必须与 my_partitions.csv 中 nvs_certs 一行保持一致！）====
# 烧录偏移不再硬编码：parttool.py 会从设备上的分区表里按分区名自动查出 nvs_certs 的偏移
$PartitionSize  = "0x8000"    # nvs_certs 分区大小
$PartitionName  = "nvs_certs" # nvs_certs 分区名

# ==== 项目路径 ====
$ProjectDir     = $PSScriptRoot
$CertsDir       = Join-Path $ProjectDir "components\use_wifi\certs"
$RootCA         = Join-Path $CertsDir "AmazonRootCA1.pem"
$DevCert        = Join-Path $CertsDir "$($DeviceId).cert.pem"
$DevKey         = Join-Path $CertsDir "$($DeviceId).private.key"
$OutputDir      = Join-Path $ProjectDir "certs_bin"
$CsvFile        = Join-Path $OutputDir "certs_$($DeviceId).csv"
$BinFile        = Join-Path $OutputDir "nvs_certs_$($DeviceId).bin"

# ==== 检查证书文件是否存在 ====
foreach ($f in @($RootCA, $DevCert, $DevKey)) {
    if (-not (Test-Path $f)) {
        Write-Host "[ERROR] 找不到证书文件: $f" -ForegroundColor Red
        Write-Host "请确保 certs 目录下有以下文件:" -ForegroundColor Yellow
        Write-Host "  AmazonRootCA1.pem"
        Write-Host "  $($DeviceId).cert.pem"
        Write-Host "  $($DeviceId).private.key"
        exit 1
    }
}

# ==== 创建输出目录 ====
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# ==== 生成 CSV（注意：必须无 BOM，否则 nvs_partition_gen.py 解析表头会 KeyError: 'key'）====
$csvContent = @"
key,type,encoding,value
certs,namespace,,
root_ca,file,binary,$RootCA
dev_cert,file,binary,$DevCert
dev_key,file,binary,$DevKey
"@
[System.IO.File]::WriteAllText($CsvFile, $csvContent, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[OK] CSV 已生成: $CsvFile" -ForegroundColor Green

# ==== 调用 nvs_partition_gen.py 生成 bin ====
Write-Host "正在生成 NVS bin 文件..." -ForegroundColor Cyan
& $IDF_PYTHON $NVS_TOOL generate $CsvFile $BinFile $PartitionSize --version 2
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] nvs_partition_gen.py 生成失败 (exit=$LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BinFile) -or (Get-Item $BinFile).Length -eq 0) {
    Write-Host "[ERROR] NVS bin 生成失败" -ForegroundColor Red
    exit 1
}

$binSize = (Get-Item $BinFile).Length
Write-Host "[OK] NVS bin 已生成: $BinFile ($binSize bytes)" -ForegroundColor Green

# ==== 可选：直接烧录 ====
if ($Flash) {
    Write-Host "正在烧录到 $Port ..." -ForegroundColor Cyan
    # parttool.py 内部用 $IDF_PATH 环境变量定位 esptool.py，必须先设置
    $env:IDF_PATH = $IDF_PATH
    # 按分区名烧录：偏移由设备上的分区表决定，my_partitions.csv 改动后无需改本脚本
    & $IDF_PYTHON $PARTTOOL `
        --port $Port --baud 460800 `
        write_partition --partition-name $PartitionName --input $BinFile

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] 证书已烧录到分区 $PartitionName ($Port)" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] 烧录失败，请检查串口和连接" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "如需烧录，运行:" -ForegroundColor Yellow
    Write-Host "  .\make_certs_bin.ps1 -DeviceId $DeviceId -Flash -Port COM3" -ForegroundColor White
}

Write-Host ""
Write-Host "完成! 用法总结:" -ForegroundColor Cyan
Write-Host "  生成: .\make_certs_bin.ps1 -DeviceId $DeviceId"
Write-Host "  生成+烧录: .\make_certs_bin.ps1 -DeviceId $DeviceId -Flash -Port COM3"
