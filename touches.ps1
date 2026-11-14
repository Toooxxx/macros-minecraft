# =====================================================================
#  touches.ps1 : touches du jeu, lues dans options.txt de Minecraft (charge par tous les scripts).
#
#  Minecraft enregistre la POSITION physique de la touche sous le nom qu'elle a sur un clavier QWERTY :
#  "key.keyboard.w" est la touche Z d'un clavier AZERTY. On convertit donc ce nom en code de position.
#  Fichier absent ou touche non geree (souris, touche speciale) : valeur par defaut pour cette touche.
# =====================================================================
# Plusieurs Minecraft ouverts (compte AFK sur le launcher normal) : on ne garde que Lunar. Pas de Lunar : on garde tout.
function Garder-Lunar($jeux) {
  $tous = @($jeux | Where-Object { $_ })
  $lunar = @($tous | Where-Object { $_.Path -match '\\\.lunarclient\\' })
  if ($lunar.Count -gt 0) { return $lunar }
  return $tous
}
function Lire-Touches($fichier) {
  $resultat = @{ avant = 0x11; arriere = 0x1F; gauche = 0x1E; droite = 0x20; chat = 0x14; accroupi = 0x2A; slots = @(0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A); lues = $false; ignorees = @() }
  if (-not (Test-Path $fichier)) { return $resultat }
  $codes = @{
    q = 0x10; w = 0x11; e = 0x12; r = 0x13; t = 0x14; y = 0x15; u = 0x16; i = 0x17; o = 0x18; p = 0x19
    a = 0x1E; s = 0x1F; d = 0x20; f = 0x21; g = 0x22; h = 0x23; j = 0x24; k = 0x25; l = 0x26
    z = 0x2C; x = 0x2D; c = 0x2E; v = 0x2F; b = 0x30; n = 0x31; m = 0x32
    '1' = 0x02; '2' = 0x03; '3' = 0x04; '4' = 0x05; '5' = 0x06; '6' = 0x07; '7' = 0x08; '8' = 0x09; '9' = 0x0A; '0' = 0x0B
    space = 0x39; tab = 0x0F; 'caps.lock' = 0x3A; 'left.shift' = 0x2A; 'right.shift' = 0x36; 'left.control' = 0x1D; 'left.alt' = 0x38
    enter = 0x1C; semicolon = 0x27; apostrophe = 0x28; comma = 0x33; period = 0x34; slash = 0x35; minus = 0x0C; equal = 0x0D
    'left.bracket' = 0x1A; 'right.bracket' = 0x1B; backslash = 0x2B; 'grave.accent' = 0x29
  }
  $noms = @{ 'key_key.forward' = 'avant'; 'key_key.back' = 'arriere'; 'key_key.left' = 'gauche'; 'key_key.right' = 'droite'; 'key_key.chat' = 'chat'; 'key_key.sneak' = 'accroupi' }
  try {
    foreach ($ligne in [IO.File]::ReadAllLines($fichier)) {
      if ($ligne -notmatch '^(key_key\.[a-z.0-9]+):key\.(keyboard\.(.+)|mouse\..+)$') { continue }
      $cle = $Matches[1]; $touche = $Matches[3]
      $slot = if ($cle -match '^key_key\.hotbar\.([1-9])$') { [int]$Matches[1] } else { 0 }
      if (-not $noms.ContainsKey($cle) -and $slot -eq 0) { continue }
      if (-not $touche -or -not $codes.ContainsKey($touche)) { $resultat.ignorees += $cle; continue }
      if ($slot -gt 0) { $resultat.slots[$slot - 1] = $codes[$touche] } else { $resultat[$noms[$cle]] = $codes[$touche] }
      $resultat.lues = $true
    }
  } catch { }
  return $resultat
}

$script:Cles = Lire-Touches (Join-Path $env:APPDATA '.minecraft\options.txt')
$script:Slots = $script:Cles.slots
# 14/11/2026 : avec /fly actif, le /home pose le joueur EN VOL (recolte des pasteques bloquee au bout d'une rangee).
# Rien dans le chat : s'accroupir en vol fait descendre, et en touchant le sol le jeu coupe le vol tout seul.
# Au sol, s'accroupir un instant ne fait rien. A appeler au demarrage de chaque ferme et apres chaque /home.
function Couper-Vol {
  $k = [uint16]$script:Cles.accroupi
  try { [Entree]::Touche($k, $true); Start-Sleep -Milliseconds 600 }
  finally { [Entree]::Touche($k, $false) }
  Start-Sleep -Milliseconds 250
  Write-Host "Vol coupe s'il etait actif (accroupi 0,6 s)."
}
$manquantes = @($script:Cles.ignorees | Where-Object { $_ -notmatch 'hotbar' })   # une case de barre sur un bouton de souris ne gene pas
if ($manquantes.Count -gt 0) { Write-Host ("Touches non gerees dans options.txt, valeurs par defaut utilisees : {0}" -f ($manquantes -join ', ')) }
