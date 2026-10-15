if (Test-MachineWideSentinel -Name 'AB-Allow-NCSOrderSheetsASR') { return }

# Carve NCS_Order_Sheets.exe out of the ASR rule "Block executable files from
# running unless they meet a prevalence, age, or trusted list criterion"
# (01443614-cd74-433a-b99e-2ecdc07bfc25). The HSS report sets that rule to Warn,
# and on PC5-FA031-4860 (15 Oct 2026) it stopped the unsigned in-house exe with
# "Windows cannot access the specified device, path or file" (Defender 1121).
#
# Only on PCs where the exe exists. Users can create folders in C:\, so adding
# the exclusion everywhere would let anyone drop an exe at that path and run it.
# For the same reason the exe itself is locked: owner Administrators,
# inheritance off, Users read+execute only. C:\NCS stays Authenticated Users:
# Modify because the app writes its data next to itself.
#
# Safe as an include (unlike the CFA override): HSS ImportReport sets ASR rule
# states as machine policy and only ever ADDS its own ASR-only exclusions; it
# never clears the list. So this does not race the async HSS apply task.

$NcsExe = 'C:\NCS\NCS_Order_Sheets.exe'

if (-not (Test-Path -LiteralPath $NcsExe -PathType Leaf)) {
    Write-Host "[INFO] $NcsExe not present; no ASR exclusion added." -ForegroundColor DarkGray
    return
}

Write-Host "[INFO] Locking $NcsExe and adding its ASR exclusion..." -ForegroundColor Cyan

# 1. Lock the exe so a user cannot replace it. Owner first: an owner can always
#    rewrite the DACL, so a user-owned exe would not stay locked.
#    S-1-5-32-544 = Administrators, S-1-5-18 = SYSTEM, S-1-5-32-545 = Users.
$aclLocked = $false
try {
    $out = & icacls.exe $NcsExe /setowner '*S-1-5-32-544' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls /setowner exited $LASTEXITCODE - $out" }
    $out = & icacls.exe $NcsExe /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F' '*S-1-5-32-545:RX' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls /grant exited $LASTEXITCODE - $out" }

    # Remove any other explicit entries (for example a user granted Modify by hand).
    $keep = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-32-545')
    $acl  = Get-Acl -LiteralPath $NcsExe
    foreach ($rule in @($acl.Access)) {
        $sid = try { $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { "$($rule.IdentityReference)" }
        if ($sid -notin $keep) {
            $out = & icacls.exe $NcsExe /remove:g "*$sid" 2>&1
            Write-Log "NCS ASR: removed extra ACE for $sid from $NcsExe ($out)"
        }
    }
    $aclLocked = $true
    Write-Log "NCS ASR: locked $NcsExe (owner Administrators; Admins/SYSTEM full, Users RX, no inheritance)"
    Write-Host "[OK] Locked $NcsExe" -ForegroundColor Green
} catch {
    Write-Log "ERROR: NCS ASR: could not lock $NcsExe - $_"
    Write-Host "[ERROR] Could not lock ${NcsExe}: $_" -ForegroundColor Red
}

# 2. Never exclude a path users can still replace.
if (-not $aclLocked) {
    Write-Log "NCS ASR: exe not locked, so the ASR exclusion was not added"
    Write-Host "[WARN] ASR exclusion skipped because the exe could not be locked" -ForegroundColor Yellow
    return
}

try {
    $current = @((Get-MpPreference -ErrorAction Stop).AttackSurfaceReductionOnlyExclusions)
    if ($current -contains $NcsExe) {
        Write-Log "NCS ASR: exclusion already present for $NcsExe"
        Write-Host "[OK] ASR exclusion already present" -ForegroundColor Green
    } else {
        Add-MpPreference -AttackSurfaceReductionOnlyExclusions $NcsExe -ErrorAction Stop
        Write-Log "NCS ASR: added ASR-only exclusion for $NcsExe"
        Write-Host "[OK] Added ASR exclusion for $NcsExe" -ForegroundColor Green
    }
} catch {
    Write-Log "ERROR: NCS ASR: could not add ASR exclusion for $NcsExe - $_"
    Write-Host "[ERROR] Could not add ASR exclusion: $_" -ForegroundColor Red
}
