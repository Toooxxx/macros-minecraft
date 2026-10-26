# =====================================================================
#  verification.ps1 : verification AFK du serveur. Charge par canne-etage.ps1, autoclic.ps1 et
#  peche.ps1 (apres le bloc C#, qui contient les classes Titre et Glyphes).
#
#  Le message (capture du 25/10/2026) : titre orange "AFK Verification", sous-titre
#  "! Veuillez saisir le nombre 91 dans le chat." avec le nombre en cyan (50,199,229), police x6.
#  Quand il apparait : 6 images dans diagnostics\verification\<date>\, lecture du nombre (2 lectures
#  identiques exigees), puis reponse dans le chat avec un temps de reaction different a chaque fois.
#  Ecrire ce nombre dans le chat : autorise par l'utilisateur le 25/10/2026 (seule exception, avec /home s).
# =====================================================================
$script:ProchaineVerif = 0; $script:FinPauseVerif = 0
# Echelle de l interface du jeu (reglage "Taille de l interface" = 3). Les zones lues sont en unites
# d interface depuis le centre ou les bords, pas en % de l ecran : 25/10/2026, sur le 2e ecran (1920 de
# large) les zones en % etaient decalees.
$script:Gui = 3
# Taille trouvee sur la barre d'objets du jeu (classe Interface) ; reste a 3 si rien de net. A appeler une fois
# au depart, jeu visible.
function Detecter-Interface {
  $jeu = Get-Process -Id $script:PidsJeu -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  if (-not $jeu) { return }
  $t = [Interface]::Taille($jeu.MainWindowHandle)
  if ($t -gt 0) { $script:Gui = $t; Write-Host ("Taille de l'interface du jeu : {0}." -f $t) }
  else { Write-Host "Taille de l'interface pas reconnue sur la barre d'objets : je garde 3." }
}
$script:CapturesRestantes = 0; $script:ProchaineCapture = 0; $script:DossierVerif = $null

function Fenetre-Jeu {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  if ($h -eq [IntPtr]::Zero) { return $null }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  if ($r.R - $r.L -lt 200) { return $null }
  return New-Object System.Drawing.Rectangle $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T)
}

# A appeler souvent (boucles d'attente) : ne travaille qu'une fois par seconde.
function Surveiller-Verification {
  $mtn = [Environment]::TickCount
  # serie d'images en cours (une toutes les 0,5 s, sans bloquer le script)
  if ($script:CapturesRestantes -gt 0 -and $mtn -ge $script:ProchaineCapture) {
    $f = Fenetre-Jeu
    if ($f) { try { [Titre]::SauverEcran($f, (Join-Path $script:DossierVerif ("{0}.png" -f (7 - $script:CapturesRestantes)))) } catch { } }
    $script:CapturesRestantes--; $script:ProchaineCapture = $mtn + 500
    return
  }
  if ($mtn -lt $script:ProchaineVerif -or $mtn -lt $script:FinPauseVerif) { return }
  $script:ProchaineVerif = $mtn + 1000
  $f = Fenetre-Jeu; if (-not $f) { return }
  $centre = New-Object System.Drawing.Rectangle ($f.X + [int]($f.Width * 0.2)), ($f.Y + [int]($f.Height * 0.2)), ([int]($f.Width * 0.6)), ([int]($f.Height * 0.4))
  $score = [Titre]::Score($centre, [int[]](6, 12))
  if ($score -lt 800) { return }                                          # ecrans normaux : 0 a 25 ; un titre : plusieurs milliers
  # Liste des joueurs (touche Tab) : des milliers de petits textes, ombre a 3 px -> 6500 a 7400 ici, mais
  # 16 000 en petit texte (25/10/2026, 8 fausses alertes). Un gros titre a des lettres pleines : peu de petit texte.
  $petit = [Titre]::Score($centre, [int[]](3))
  if ($score -lt 2 * $petit) { return }
  $racine = Join-Path $Dossier 'diagnostics\verification'
  $script:DossierVerif = Join-Path $racine (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
  New-Item -ItemType Directory -Force $script:DossierVerif | Out-Null
  $script:CapturesRestantes = 6; $script:ProchaineCapture = 0
  $script:FinPauseVerif = $mtn + 60000                                    # une serie par minute au plus
  Write-Host ("Gros message au centre de l'ecran (verification ?) : images dans diagnostics\verification\{0} (score {1}, petit texte {2})." -f (Split-Path $script:DossierVerif -Leaf), $score, $petit)
  # 20 series au plus : les plus anciennes sont effacees
  Get-ChildItem $racine -Directory | Sort-Object Name -Descending | Select-Object -Skip 20 | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  try { [Titre]::SauverEcran($f, (Join-Path $script:DossierVerif '0.png')) } catch { }   # image avant la reponse
  return (Repondre-Verification $f)
}

# Lit le nombre cyan du sous-titre ; $null si pas lu deux fois de suite pareil (en 6 s au plus).
function Lire-NombreVerif($f) {
  $ech = 2 * $script:Gui                                                  # sous-titre : 2 x l echelle de l interface
  $zone = New-Object System.Drawing.Rectangle ($f.X + [int]($f.Width * 0.2)), ($f.Y + [int]($f.Height * 0.50)), ([int]($f.Width * 0.6)), ([int]($f.Height * 0.12))
  $avant = $null; $fin = [Environment]::TickCount + 6000
  while ([Environment]::TickCount -lt $fin) {
    $t = [Glyphes]::LireCouleur($zone, 50, 199, 229, $ech)
    if ($t -match '^\d{1,4}$') { if ($t -eq $avant) { return $t }; $avant = $t } else { $avant = $null }
    Start-Sleep -Milliseconds 250                                           # le message clignote : on relit
  }
  return $null
}

# Repond dans le chat. Renvoie $true si le script a ete interrompu (touches relachees puis reprises),
# pour que l'appelant reprenne comme apres une pause.
function Repondre-Verification($f) {
  $nombre = Lire-NombreVerif $f
  if ($RepondreVerif -ne 1) {                                              # option du menu desactivee : on previent seulement
    Write-Host ("Verification AFK a l'ecran{0} : reponse automatique desactivee (Options du menu), a toi de repondre." -f $(if ($nombre) { " (nombre $nombre)" } else { '' }))
    for ($k = 0; $k -lt 3; $k++) { [console]::Beep(1200, 250); Start-Sleep -Milliseconds 120 }
    return $false
  }
  if ($null -eq $nombre) { Write-Host "Verification : nombre pas lu avec certitude, je ne reponds pas (images enregistrees)."; return $false }
  # on lache tout tout de suite (sinon la ferme continuerait seule pendant l'attente), en notant ce qui etait tenu
  $touche = $script:ToucheTenue; $clic = $script:ClicTenu; $tenu = $script:Tenu
  Relacher-Tout
  $delai = Get-Random -Minimum 2500 -Maximum 8000                           # temps de reaction different a chaque fois
  Write-Host ("Verification AFK : nombre {0}, reponse dans {1:N1} s." -f $nombre, ($delai / 1000))
  Start-Sleep -Milliseconds $delai
  if (-not (Au-Premier-Plan)) { Write-Host "Verification : le jeu n'est pas au premier plan, reponse annulee."; return $true }
  [Entree]::Touche(0x14, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 80); [Entree]::Touche(0x14, $false)   # T : ouvre le chat
  Start-Sleep -Milliseconds (Get-Random -Minimum 350 -Maximum 900)
  foreach ($ch in $nombre.ToCharArray()) {
    if ([Fond]::Actif) { [Fond]::Caractere($ch) } else { [System.Windows.Forms.SendKeys]::SendWait([string]$ch) }
    Start-Sleep -Milliseconds (Get-Random -Minimum 90 -Maximum 280)          # ecart variable entre les touches
  }
  Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 650)
  [Entree]::Touche(0x1C, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 80); [Entree]::Touche(0x1C, $false)   # Entree
  Start-Sleep -Milliseconds 2000
  $f2 = Fenetre-Jeu
  $reste = if ($f2) { [Titre]::Score((New-Object System.Drawing.Rectangle ($f2.X + [int]($f2.Width * 0.2)), ($f2.Y + [int]($f2.Height * 0.2)), ([int]($f2.Width * 0.6)), ([int]($f2.Height * 0.4))), [int[]](6, 12)) } else { 0 }
  if ($reste -lt 800) { Write-Host ("Verification AFK : {0} envoye, le message a disparu." -f $nombre) }
  else { Write-Host ("Verification AFK : {0} envoye, mais le message est toujours affiche (a verifier)." -f $nombre) }
  Start-Sleep -Milliseconds (Get-Random -Minimum 400 -Maximum 1200)
  # on reprend ce qui etait tenu
  if ($touche) { Enfoncer $touche }
  if ($clic) { Clic $true }
  if ($tenu) { Bouton $true }
  return $true
}
