# =====================================================================
#  verification.ps1 : verification AFK du serveur. Charge par canne-etage.ps1, autoclic.ps1 et
#  peche.ps1 (apres le bloc C#, qui contient les classes Titre et Glyphes).
#
#  Le message (capture du 25/10/2026) : titre orange "AFK Verification", sous-titre
#  "! Veuillez saisir le nombre 91 dans le chat." avec le nombre en cyan (50,199,229), police x6.
#  Quand il apparait : 6 images dans diagnostics\verification\<date>\, lecture du nombre (2 lectures
#  identiques exigees), puis reponse dans le chat avec un temps de reaction different a chaque fois.
#  Ecrire ce nombre dans le chat : autorise par l'utilisateur le 25/10/2026 (avec /home canne).
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

# Journal des verifications (diagnostics\verifications.csv), lu par la page Statistiques du menu.
# Colonnes : date;mode;nombre;reponse;resultat;dossier. Mode = celui du menu (canne, peche, autoclick).
$script:ModeVerif = switch -Wildcard ((Split-Path -Leaf $MyInvocation.PSCommandPath)) { 'peche*' { 'peche' } 'autoclic*' { 'autoclick' } default { 'canne' } }
function Noter-Verification($nombre, $reponse, $resultat) {
  try {
    $f = Join-Path $Dossier 'diagnostics\verifications.csv'
    if (-not (Test-Path $f)) { Set-Content $f 'date;mode;nombre;reponse;resultat;dossier' -Encoding UTF8 }
    Add-Content $f ('{0:yyyy-MM-dd HH:mm:ss};{1};{2};{3};{4};{5}' -f (Get-Date), $script:ModeVerif, $nombre, $reponse, $resultat, (Split-Path $script:DossierVerif -Leaf)) -Encoding UTF8
  } catch { }
}

function Fenetre-Jeu {
  $h = [IntPtr]::Zero
  foreach ($p in $script:PidsJeu) { $m = (Get-Process -Id $p -ErrorAction SilentlyContinue).MainWindowHandle; if ($m -ne [IntPtr]::Zero) { $h = $m } }
  if ($h -eq [IntPtr]::Zero) { return $null }
  $r = New-Object Entree+RECT; [void][Entree]::GetWindowRect($h, [ref]$r)
  if ($r.R - $r.L -lt 200) { return $null }
  return New-Object System.Drawing.Rectangle $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T)
}

# 800 en interface x3, ajuste a la taille reelle (le score compte des pixels, donc la surface du texte).
function Seuil-Titre { return [int](800 * $script:Gui * $script:Gui / 9) }

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
  # L'ombre des titres est decalee de 2 et 4 x la taille de l'interface, et le score grandit comme la surface du texte.
  $score = [Titre]::Score($centre, [int[]]@((2 * $script:Gui), (4 * $script:Gui)))
  if ($score -lt (Seuil-Titre)) { return }                                # ecrans normaux : 0 a 25 ; un titre : plusieurs milliers
  # Liste des joueurs (touche Tab) : des milliers de petits textes, ombre a 3 px -> 6500 a 7400 ici, mais
  # 16 000 en petit texte (25/10/2026, 8 fausses alertes). Un gros titre a des lettres pleines : peu de petit texte.
  $petit = [Titre]::Score($centre, [int[]]($script:Gui))
  if ($score -lt 2 * $petit) { return }
  # Le titre orange "Recompense disponible !" (/reward, toutes les 80 min environ : 07/11/2026, 12 fausses
  # alertes en 8 h) ressemble a la verification mais n'a pas de nombre cyan : on l'ignore sans rien enregistrer.
  if (-not (Nombre-Cyan-Present $f)) {
    $script:FinPauseVerif = $mtn + 60000
    if ($script:Journal) { try { Add-Content $script:Journal ("{0:HH:mm:ss.fff} verification : gros titre sans nombre cyan, ignore (score {1})" -f (Get-Date), $score) } catch { } }
    return
  }
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

function Zone-SousTitre($f) { return New-Object System.Drawing.Rectangle ($f.X + [int]($f.Width * 0.2)), ($f.Y + [int]($f.Height * 0.50)), ([int]($f.Width * 0.6)), ([int]($f.Height * 0.12)) }
# Un pixel au moins de la couleur du nombre (cyan) sous le titre, en 3 s (le message clignote) ?
function Nombre-Cyan-Present($f) {
  $zone = Zone-SousTitre $f; $fin = [Environment]::TickCount + 3000
  while ([Environment]::TickCount -lt $fin) {
    if ([Glyphes]::LireCouleur($zone, 50, 199, 229, 2 * $script:Gui) -ne '') { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}
# Lit le nombre cyan du sous-titre ; $null si pas lu deux fois de suite pareil (en 6 s au plus).
function Lire-NombreVerif($f) {
  $ech = 2 * $script:Gui                                                  # sous-titre : 2 x l echelle de l interface
  $zone = Zone-SousTitre $f
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
    Noter-Verification $nombre 'manuelle' 'a toi de repondre'
    return $false
  }
  if ($null -eq $nombre) { Write-Host "Verification : nombre pas lu avec certitude, je ne reponds pas (images enregistrees)."; Noter-Verification '' 'auto' 'nombre pas lu'; return $false }
  # on lache tout tout de suite (sinon la ferme continuerait seule pendant l'attente), en notant ce qui etait tenu
  $touche = $script:ToucheTenue; $clic = $script:ClicTenu; $tenu = $script:Tenu
  Relacher-Tout
  $delai = Get-Random -Minimum 2500 -Maximum 8000                           # temps de reaction different a chaque fois
  Write-Host ("Verification AFK : nombre {0}, reponse dans {1:N1} s." -f $nombre, ($delai / 1000))
  Start-Sleep -Milliseconds $delai
  if (-not (Au-Premier-Plan)) { Write-Host "Verification : le jeu n'est pas au premier plan, reponse annulee."; Noter-Verification $nombre 'auto' 'annulee (jeu pas au premier plan)'; return $true }
  [Entree]::Touche($script:Cles.chat, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 80); [Entree]::Touche($script:Cles.chat, $false)   # ouvre le chat
  Start-Sleep -Milliseconds (Get-Random -Minimum 350 -Maximum 900)
  foreach ($ch in $nombre.ToCharArray()) {
    if ([Fond]::Actif) { [Fond]::Caractere($ch) } else { [System.Windows.Forms.SendKeys]::SendWait([string]$ch) }
    Start-Sleep -Milliseconds (Get-Random -Minimum 90 -Maximum 280)          # ecart variable entre les touches
  }
  Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 650)
  [Entree]::Touche(0x1C, $true); Start-Sleep -Milliseconds (Get-Random -Minimum 30 -Maximum 80); [Entree]::Touche(0x1C, $false)   # Entree
  Start-Sleep -Milliseconds 2000
  $f2 = Fenetre-Jeu
  $reste = if ($f2) { [Titre]::Score((New-Object System.Drawing.Rectangle ($f2.X + [int]($f2.Width * 0.2)), ($f2.Y + [int]($f2.Height * 0.2)), ([int]($f2.Width * 0.6)), ([int]($f2.Height * 0.4))), [int[]]@((2 * $script:Gui), (4 * $script:Gui))) } else { 0 }
  if ($reste -lt (Seuil-Titre)) { Write-Host ("Verification AFK : {0} envoye, le message a disparu." -f $nombre); Noter-Verification $nombre 'auto' 'reussie' }
  else { Write-Host ("Verification AFK : {0} envoye, mais le message est toujours affiche (a verifier)." -f $nombre); Noter-Verification $nombre 'auto' 'message toujours affiche' }
  Start-Sleep -Milliseconds (Get-Random -Minimum 400 -Maximum 1200)
  # on reprend ce qui etait tenu
  if ($touche) { Enfoncer $touche }
  if ($clic) { Clic $true }
  if ($tenu) { Bouton $true }
  return $true
}
