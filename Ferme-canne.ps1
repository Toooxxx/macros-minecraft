# Ferme-canne.ps1 : lance le menu de la ferme a canne sans .exe.
# (Windows 11 "Controle intelligent des applications" bloque le .exe non signe ;
#  ici le menu est compile en memoire par PowerShell, qui est signe par Microsoft.)
$dossier = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:FERME_CANNE_DOSSIER = $dossier + '\'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# Mise a jour depuis GitHub (avant de compiler le menu, pour qu'il soit deja a jour)
$maj = Join-Path $dossier 'mise-a-jour.ps1'
if (Test-Path $maj) { try { & $maj -Dossier $dossier } catch { } }
Add-Type -TypeDefinition (Get-Content (Join-Path $dossier 'menu\FermeCanne.cs') -Raw) -ReferencedAssemblies System.Windows.Forms, System.Drawing
[FermeCanne]::Main()
