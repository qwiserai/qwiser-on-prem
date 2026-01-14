<#
.SYNOPSIS
    Approves Front Door Private Endpoint connection to Private Link Service.

.DESCRIPTION
    This script approves the pending private endpoint connection from Azure Front Door
    to the Private Link Service (PLS) that fronts the AKS internal load balancer.

    Background:
    - Front Door creates a PE connection to the PLS during deployment
    - The connection is initially in "Pending" state
    - This script approves the connection to enable traffic flow

.PARAMETER ResourceGroup
    Resource group containing the Private Link Service.

.PARAMETER PlsName
    Name of the Private Link Service.

.EXAMPLE
    ./approve-pe-connection.ps1 -ResourceGroup "qwiser-prod-rg" -PlsName "qwiser-prod-pls"

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in
    - Network Contributor role on the resource group containing the PLS
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$PlsName
)

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Private Endpoint Connection Approval" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Private Link Service: $PlsName"
Write-Host ""

# Get PLS details
Write-Host "Fetching Private Link Service details..." -ForegroundColor Gray

$plsJson = az network private-link-service show `
    --resource-group $ResourceGroup `
    --name $PlsName `
    --query "privateEndpointConnections" `
    -o json 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to get PLS details. Verify the resource group and PLS name." -ForegroundColor Red
    exit 1
}

$connections = $plsJson | ConvertFrom-Json

if (-not $connections -or $connections.Count -eq 0) {
    Write-Host "No PE connections found on this PLS." -ForegroundColor Yellow
    Write-Host "The Front Door may not have completed its PE connection yet."
    Write-Host "Wait a few minutes and try again."
    exit 0
}

# Filter pending connections
$pendingConnections = $connections | Where-Object { $_.privateLinkServiceConnectionState.status -eq "Pending" }
$approvedConnections = $connections | Where-Object { $_.privateLinkServiceConnectionState.status -eq "Approved" }

if (-not $pendingConnections -or $pendingConnections.Count -eq 0) {
    Write-Host "No pending connections found." -ForegroundColor Yellow
    Write-Host ""

    if ($approvedConnections -and $approvedConnections.Count -gt 0) {
        Write-Host "Found approved connections:" -ForegroundColor Green
        foreach ($conn in $approvedConnections) {
            $connName = $conn.name
            Write-Host "  [OK] $connName" -ForegroundColor Green
        }
    }
    exit 0
}

# Approve pending connections
Write-Host "Found pending connections:" -ForegroundColor Gray
foreach ($conn in $pendingConnections) {
    Write-Host "  - $($conn.name)"
}
Write-Host ""

$approvedCount = 0
$failedCount = 0

foreach ($conn in $pendingConnections) {
    $connectionName = $conn.name

    Write-Host "[Approving] $connectionName" -ForegroundColor Gray

    az network private-link-service connection update `
        --resource-group $ResourceGroup `
        --name $connectionName `
        --service-name $PlsName `
        --connection-status "Approved" `
        --description "Approved by post-deploy script" `
        --output none 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $connectionName approved" -ForegroundColor Green
        $approvedCount++
    } else {
        Write-Host "[FAILED] Failed to approve $connectionName" -ForegroundColor Red
        $failedCount++
    }
}

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "PE Connection Approval Complete" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Verify final state
Write-Host "Final connection states:" -ForegroundColor White
az network private-link-service show `
    --resource-group $ResourceGroup `
    --name $PlsName `
    --query "privateEndpointConnections[].{Name:name, Status:privateLinkServiceConnectionState.status}" `
    -o table

Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Verify Front Door health probes are passing" -ForegroundColor Gray
Write-Host "  2. Test connectivity through Front Door endpoint" -ForegroundColor Gray
Write-Host ""
