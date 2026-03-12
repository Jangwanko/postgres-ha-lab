Set-StrictMode -Version Latest

$script:DbUser = "postgres"
$script:DbPassword = "postgres"
$script:DbName = "postgres"
$script:PgpoolContainer = "pgpool"
$script:ClusterNetwork = "pg_ha_net"
$script:DbNodes = @("pg_node1", "pg_node2", "pg_node3")
$script:PsqlBin = "/opt/bitnami/postgresql/bin/psql"
$script:ComposeProjectName = "postgres-ha-lab"

function Invoke-DbQuery {
  param(
    [Parameter(Mandatory = $true)][string]$Container,
    [Parameter(Mandatory = $true)][string]$Sql
  )

  try {
    $result = docker exec -e "PGPASSWORD=$script:DbPassword" $Container $script:PsqlBin -h 127.0.0.1 -U $script:DbUser -d $script:DbName -t -A -c $Sql 2>$null
    return ($result | Out-String).Trim()
  } catch {
    return ""
  }
}

function Test-ContainerRunning {
  param([Parameter(Mandatory = $true)][string]$Container)

  try {
    return ((docker inspect -f "{{.State.Running}}" $Container 2>$null) | Out-String).Trim() -eq "true"
  } catch {
    return $false
  }
}

function Get-CurrentPrimary {
  foreach ($node in $script:DbNodes) {
    if (Test-ContainerRunning -Container $node) {
      if ((Invoke-DbQuery -Container $node -Sql "select pg_is_in_recovery();") -eq "f") {
        return $node
      }
    }
  }
  return $null
}

function Get-CurrentReplicas {
  $replicas = @()
  foreach ($node in $script:DbNodes) {
    if (Test-ContainerRunning -Container $node) {
      if ((Invoke-DbQuery -Container $node -Sql "select pg_is_in_recovery();") -eq "t") {
        $replicas += $node
      }
    }
  }
  return $replicas
}

function Wait-ForPrimaryChange {
  param(
    [Parameter(Mandatory = $true)][string]$OldPrimary,
    [int]$TimeoutSeconds = 120,
    [int]$IntervalSeconds = 2
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $candidate = Get-CurrentPrimary
    if ($candidate -and $candidate -ne $OldPrimary) {
      return $candidate
    }
    Start-Sleep -Seconds $IntervalSeconds
  }

  return $null
}

function Wait-ForReplicaRole {
  param(
    [Parameter(Mandatory = $true)][string]$Node,
    [int]$TimeoutSeconds = 180,
    [int]$IntervalSeconds = 2
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-ContainerRunning -Container $Node) {
      if ((Invoke-DbQuery -Container $Node -Sql "select pg_is_in_recovery();") -eq "t") {
        return $true
      }
    }
    Start-Sleep -Seconds $IntervalSeconds
  }

  return $false
}

function Wait-ForPgpool {
  param(
    [int]$TimeoutSeconds = 120,
    [int]$IntervalSeconds = 2
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      docker exec $script:PgpoolContainer bash -lc ": > /dev/tcp/127.0.0.1/5432" *> $null
      if ($LASTEXITCODE -eq 0) {
        return $true
      }
    } catch {
    }
    Start-Sleep -Seconds $IntervalSeconds
  }

  return $false
}

function Get-ServiceNameFromNode {
  param([Parameter(Mandatory = $true)][string]$Node)

  switch ($Node) {
    "pg_node1" { return "pg-node-1" }
    "pg_node2" { return "pg-node-2" }
    "pg_node3" { return "pg-node-3" }
    default { throw "Unknown node name: $Node" }
  }
}

function Get-VolumeNameFromNode {
  param([Parameter(Mandatory = $true)][string]$Node)

  switch ($Node) {
    "pg_node1" { return "$script:ComposeProjectName`_node1_data" }
    "pg_node2" { return "$script:ComposeProjectName`_node2_data" }
    "pg_node3" { return "$script:ComposeProjectName`_node3_data" }
    default { throw "Unknown node name: $Node" }
  }
}
