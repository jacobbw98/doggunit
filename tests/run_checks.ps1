param([string]$GodotPath = 'godot')

$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'doggunit-checks'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$suites = @(
    'test_world_generation',
    'portal_regression',
    'player_physics_regression',
    'combat_regression',
    'mappo_shoot_regression',
    'run_progression_regression',
    'ui_items_regression',
    'item_families_regression',
    'catalog_updates_regression',
    'catalog_expansion_assets_regression',
    'reload_item_stack_regression',
    'unimate_reload_regression',
    'freeze_projectile_modifier_check',
    'key_room_lock_check',
    'creature_roster_regression',
    'item_interaction_regression',
    'economy_regression',
    'shop_layout_regression',
    'mildred_tracking_regression',
    'bomb_inventory_regression',
    'portal_lock_integration',
    'portal_combat_entry_regression',
    'enemy_portal_containment_regression',
    'minimap_targeting_regression'
)
$failed = @()
foreach ($suite in $suites) {
    $logPath = Join-Path $logDirectory ($suite + '.log')
    $output = & $GodotPath --headless --path $projectPath --script ('res://tests/' + $suite + '.gd') 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $logPath -Encoding utf8
    if ($exitCode -ne 0 -or ($output -match '(^SCRIPT ERROR:|^ERROR:)')) {
        $failed += $suite
        Write-Output ('FAIL ' + $suite + ' — ' + $logPath)
        $output | Select-Object -Last 15 | Write-Output
    } else {
        Write-Output ('PASS ' + $suite)
    }
}
if ($failed.Count -gt 0) {
    Write-Output ('Failed suites: ' + ($failed -join ', '))
    exit 1
}
Write-Output ('All ' + $suites.Count + ' suites passed. Logs: ' + $logDirectory)
