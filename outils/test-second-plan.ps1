# =====================================================================
#  test-second-plan.ps1 : le jeu accepte-t-il des touches et des clics quand il est au SECOND PLAN ?
#
#  Les commandes sont envoyees DIRECTEMENT a la fenetre de Minecraft (PostMessage), jamais a la fenetre
#  au premier plan : ta table de poker ou ton navigateur ne recoivent rien. Rien n'est ecrit dans le chat.
#
#  Avant : dans le jeu, F3 + P (desactive la pause quand le jeu perd la main), canne a peche au slot 1
#  en main, face a l'eau (ou face a un bloc pour le test 3). Ensuite clique sur une AUTRE fenetre.
#
#  LANCEMENT :
#    powershell -ExecutionPolicy Bypass -File "D:\macros-minecraft\outils\test-second-plan.ps1"
# =====================================================================
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SecondPlan {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  // position du clic : centre de la zone de jeu (coordonnees dans la fenetre)
  public static IntPtr Centre(IntPtr h) { RECT r; GetClientRect(h, out r); int x = (r.R - r.L) / 2, y = (r.B - r.T) / 2; return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  // touche : code virtuel + code de position (scancode), comme une vraie frappe
  public static void Touche(IntPtr h, int vk, int scan, bool bas) {
    long l = 1 | ((long)scan << 16);
    if (!bas) l |= (1L << 30) | (1L << 31);
    PostMessage(h, bas ? 0x0100u : 0x0101u, (IntPtr)vk, (IntPtr)l);
  }
}
'@

$jeu = Get-Process -Name javaw, java -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
if (-not $jeu) { Write-Host "Le jeu n'est pas lance." -ForegroundColor Red; return }
$h = $jeu.MainWindowHandle
Write-Host ("Fenetre du jeu : '{0}'" -f $jeu.MainWindowTitle)
Write-Host "Dans le jeu : F3 + P (pas de pause au second plan), canne au slot 1 en main, face a l'eau." -ForegroundColor Cyan
Write-Host "Puis clique sur une AUTRE fenetre (poker, navigateur...). Le test attend que le jeu ne soit plus au premier plan." -ForegroundColor Cyan

$fin = [Environment]::TickCount + 120000
while ([SecondPlan]::GetForegroundWindow() -eq $h) {
  if ([Environment]::TickCount -gt $fin) { Write-Host "Le jeu est reste au premier plan : test annule." -ForegroundColor Red; return }
  Start-Sleep -Milliseconds 200
}
Write-Host "Le jeu est au second plan. Debut dans 3 s : regarde le jeu sur l'autre ecran." -ForegroundColor Green
Start-Sleep -Seconds 3
$centre = [SecondPlan]::Centre($h)

Write-Host "`nTest 1 : touche 2 (le slot 2 doit se selectionner, puis le 1 dans 2 s)" -ForegroundColor Yellow
[SecondPlan]::Touche($h, 0x32, 0x03, $true); Start-Sleep -Milliseconds 60; [SecondPlan]::Touche($h, 0x32, 0x03, $false)
Start-Sleep -Seconds 2
[SecondPlan]::Touche($h, 0x31, 0x02, $true); Start-Sleep -Milliseconds 60; [SecondPlan]::Touche($h, 0x31, 0x02, $false)
Start-Sleep -Seconds 3

Write-Host "Test 2 : un clic droit (la ligne doit se lancer)" -ForegroundColor Yellow
[void][SecondPlan]::PostMessage($h, 0x0204, [IntPtr]2, $centre); Start-Sleep -Milliseconds 70; [void][SecondPlan]::PostMessage($h, 0x0205, [IntPtr]0, $centre)
Start-Sleep -Seconds 4
Write-Host "         (un 2e clic droit pour ramener la ligne)"
[void][SecondPlan]::PostMessage($h, 0x0204, [IntPtr]2, $centre); Start-Sleep -Milliseconds 70; [void][SecondPlan]::PostMessage($h, 0x0205, [IntPtr]0, $centre)
Start-Sleep -Seconds 3

Write-Host "Test 3 : clic gauche tenu 2 s (le bras doit taper / casser le bloc vise)" -ForegroundColor Yellow
[void][SecondPlan]::PostMessage($h, 0x0201, [IntPtr]1, $centre); Start-Sleep -Seconds 2; [void][SecondPlan]::PostMessage($h, 0x0202, [IntPtr]0, $centre)

Write-Host "`nTermine. Dis-moi pour chaque test (1, 2, 3) si quelque chose s'est passe dans le jeu." -ForegroundColor Green
Write-Host "(Pense a remettre F3 + P si tu veux que le jeu se remette en pause tout seul au second plan.)"
