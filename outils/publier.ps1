# publier.ps1 : envoie la version actuelle sur GitHub pour que les autres joueurs la recoivent.
# Usage : powershell -File outils\publier.ps1 "ce qui change" ["autre nouveaute" ...]
# Augmente le numero de version.txt, y ecrit les nouveautes, puis commit + push.
param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Nouveautes)
$dossier = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$fichier = Join-Path $dossier 'version.txt'
$n = 0
if ((Test-Path $fichier) -and ((Get-Content $fichier -TotalCount 1) -match '^\s*(\d+)')) { $n = [int]$Matches[1] }
$n++
Set-Content $fichier (@("$n") + $Nouveautes) -Encoding ASCII
git -C $dossier add -A
git -C $dossier commit -q -m ("Version $n : " + ($Nouveautes -join ' ; '))
git -C $dossier push -q origin main
if ($LASTEXITCODE -eq 0) { "Version $n publiee." } else { "Echec de l'envoi sur GitHub (version $n enregistree en local)." }
