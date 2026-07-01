param(
    [string]$TerraformDir = "",
    [string]$VpcId = "",
    [string]$ClusterName = "",
    [string]$Region = "",
    [string]$TemplatePath = (Join-Path $PSScriptRoot "..\kustomize\platform-services\aws-load-balancer-controller\values.yaml"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\kustomize\platform-services\aws-load-balancer-controller\values.yaml")
)

$ErrorActionPreference = "Stop"

if (-not $ClusterName) {
    $ClusterName = $env:CLUSTER_NAME
}
if (-not $ClusterName) {
    $ClusterName = "eks-devsecops-dev-cluster"
}

if (-not $Region) {
    $Region = $env:AWS_REGION
}
if (-not $Region) {
    $Region = "ap-southeast-1"
}

if ($TerraformDir) {
    $resolvedTerraformDir = Resolve-Path $TerraformDir -ErrorAction Stop
    Push-Location $resolvedTerraformDir
    try {
        if (-not $VpcId) {
            $terraformOutput = terraform output -raw vpc_id 2>$null
            if ($LASTEXITCODE -eq 0 -and $terraformOutput) {
                $VpcId = $terraformOutput.Trim()
            }
        }

        if (-not $ClusterName -or $ClusterName -eq "eks-devsecops-dev-cluster") {
            $terraformClusterName = terraform output -raw cluster_name 2>$null
            if ($LASTEXITCODE -eq 0 -and $terraformClusterName) {
                $ClusterName = $terraformClusterName.Trim()
            }
        }

        if (-not $Region -or $Region -eq "ap-southeast-1") {
            $terraformRegion = terraform output -raw aws_region 2>$null
            if ($LASTEXITCODE -eq 0 -and $terraformRegion) {
                $Region = $terraformRegion.Trim()
            }
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $VpcId) {
    $VpcId = $env:VPC_ID
}

if (-not $VpcId) {
    throw "VPC ID was not provided. Pass -VpcId or run from a Terraform directory that exposes terraform output -raw vpc_id."
}

$templateFullPath = Resolve-Path $TemplatePath -ErrorAction Stop
$content = Get-Content -LiteralPath $templateFullPath -Raw
$content = $content.Replace("__CLUSTER_NAME__", $ClusterName)
$content = $content.Replace("__AWS_REGION__", $Region)
$content = $content.Replace("__VPC_ID__", $VpcId)

$outputFullPath = $OutputPath
if (-not [System.IO.Path]::IsPathRooted($outputFullPath)) {
    $outputFullPath = Join-Path (Get-Location) $outputFullPath
}

$parentDir = Split-Path -Parent $outputFullPath
if ($parentDir -and -not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

Set-Content -LiteralPath $outputFullPath -Value $content -NoNewline
Write-Host "Rendered values written to $outputFullPath"
