<#
    .SYNOPSIS
    Renames asset files to appropriate names required by Flipper Zero

    .DESCRIPTION
    Validates frame image files within an asset folder's current directory and renames them appropriately.
    Also provides method to generate a basic meta file.

    .PARAMETER GenerateMetaFile
    Specify this switch to dynamically generate a meta file from the frame image files
    This currently does not support bubbles within the meta file - you will need to manually modify that if you want to leverage it

    .EXAMPLE
    FrameRenamer.ps1

    .EXAMPLE
    FrameRenamer.ps1 -GenerateMetaFile

    .NOTES
    Author: 5mendo4
#>

[cmdletbinding()]

param (
    [switch]$GenerateMetaFile
)

$ErrorActionPreference = 'stop'
try {
    $FrameFiles = Get-ChildItem | Where-Object {$_.Extension -eq '.png'}
    if (($FrameFiles | Measure-Object).Count -eq 0) {
        Write-Error "No .png files found to rename"
    }
    if (($FrameFiles | Measure-Object).Count -gt 50) {
        Write-Warning "More than 50 frame files detected - recommend to reduce to less than 50 files for performance"
    }
    
    foreach ($file in ($FrameFiles | Sort-Object Name)) {
        $ImageDeets = [System.Drawing.Image]::FromFile($file.FullName)
        if ($ImageDeets.Width -ne 128 -or $ImageDeets.Height -ne 64) {
            Write-Error "One or more of the frame images is not 128x64 pixels"
        }
        $ImageDeets.Dispose()
    }   

    $index = 0
    $FrameOrder = ""

    foreach ($file in ($FrameFiles | Sort-Object Name)) {
        try {
            Rename-Item -LiteralPath "$($file.FullName)" -NewName "frame_$($index).png" -Force
        }
        catch {
            if ($_.Exception.Message -notlike '*Cannot create a file when that file already exists.*') {
                Write-Error $_.Exception.Message
            }
        }
        $FrameOrder += "$index "
        $index++
    }

    if ($GenerateMetaFile) {
        $FrameOrder += "0"
        $PassiveFrames = ($FrameFiles | Measure-Object).Count
        $MetaFileTemplate = @"
Filetype: Flipper Animation
Version: 1

Width: 128
Height: 64
Passive frames: $PassiveFrames
Active frames: 1
Frames order: $FrameOrder
Active cycles: 1
Frame rate: 4
Duration: 3600
Active cooldown: 5

Bubble slots: 0
"@
        $MetaFileTemplate | Out-File -FilePath .\meta.txt -Force
    }
}
catch {
    Write-Output $_
}
