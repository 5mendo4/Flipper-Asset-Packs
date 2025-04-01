<#
    .SYNOPSIS
    Converts .png file type to .bm file type

    .DESCRIPTION
    Parses through a source folder to convert all .png file types to proprietary .bm file types recognized by the Flipper Zero

    .PARAMETER SourceFolder
    Folder path where .png files are stored

    .PARAMETER DestinationFolder
    Folder path where .bm files will be output to

    .EXAMPLE
    pngToBmConverter.ps1 -SourceFolder 'C:\Flipper\Uncompiled' -DestinationFolder 'C:\Flipper\Compiled'

    .NOTES
    Author: 5mendo5
#>

[cmdletbinding()]

param (
    [parameter(Mandatory=$true)][string]$SourceFolder,
    [parameter(Mandatory=$true)][string]$DestinationFolder,
    [parameter(Mandatory=$false)][switch]$GenerateMetaFile
)

$ErrorActionPreference = 'stop'

try {
    Write-Output "Validating source folder exists: $SourceFolder"
    if (-not (Test-Path $SourceFolder)) {
        Write-Error "Source folder does not exist: `'$SourceFolder`'"
    }

    Write-Output "Validating destination folder: $DestinationFolder"
    if (-not (Test-Path $DestinationFolder)) {
        New-Item -ItemType Directory -Path $DestinationFolder | Out-Null
    }

    Write-Output "Validating .png files within source folder"
    $FrameFiles = Get-ChildItem -Path $SourceFolder -Filter "*.png"

    if (($FrameFiles).Count -eq 0) {
        Write-Error "No .png files found to convert"
    }
    if (($FrameFiles).Count -gt 50) {
        Write-Warning "More than 50 frame files detected - recommend reducing to under 50 for performance"
    }

    foreach ($file in ($FrameFiles | Sort-Object Name)) {
        $ImageDeets = [System.Drawing.Image]::FromFile($file.FullName)
        if ($ImageDeets.Width -ne 128 -or $ImageDeets.Height -ne 64) {
            Write-Error "One or more of the frame images is not 128x64 pixels"
        }
        $ImageDeets.Dispose()
    }

    Add-Type -AssemblyName System.Drawing

    Write-Output "Processing .png files"
    $index = 0
    $FrameOrder = ""
    foreach ($file in ($FrameFiles | Sort-Object Name)) {
        $inputPath = $file.FullName
        $outputPath = "$DestinationFolder\frame_$index.bm"

        $bitmap = [System.Drawing.Bitmap]::FromFile($inputPath)

        if ($bitmap.PixelFormat -ne 'Format1bppIndexed') {
            Write-Warning "Image is not 1-bit: $inputPath"
            continue
        }

        $width = $bitmap.Width
        $height = $bitmap.Height

        $rawBytes = New-Object System.Collections.Generic.List[Byte]

        for ($y = 0; $y -lt $height; $y++) {
            $bitBuffer = 0
            $bitCount = 0

            for ($x = 0; $x -lt $width; $x++) {
                $color = $bitmap.GetPixel($x, $y)

                # Keep image as-is: black = 1, white = 0
                $bit = if ($color.R -eq 0) { 1 } else { 0 }

                # Pack LSB-first (Flipper/XBM-style)
                $bitBuffer = $bitBuffer -bor ($bit -shl $bitCount)
                $bitCount++

                if ($bitCount -eq 8) {
                    $rawBytes.Add([byte]$bitBuffer)
                    $bitBuffer = 0
                    $bitCount = 0
                }
            }

            if ($bitCount -gt 0) {
                $rawBytes.Add([byte]$bitBuffer)
            }
        }

        # Add 0x00 header to indicate uncompressed format
        $finalBytes = New-Object System.Collections.Generic.List[Byte]
        $finalBytes.Add(0x00)
        $finalBytes.AddRange($rawBytes)

        [System.IO.File]::WriteAllBytes($outputPath, $finalBytes.ToArray())
        Write-Output "Converted: $($file.Name)"
        $FrameOrder += "$index "
        $index++
    }

    if ($GenerateMetaFile) {
        Write-Output "Generating meta.txt file"
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
        $MetaFileTemplate | Out-File -FilePath "$DestinationFolder\meta.txt" -Encoding utf8 -Force
    }
    else {
        # Check if meta file already exists
        if (Test-Path "$SourceFolder\meta.txt") {
            # Ensure meta file is encoded correctly as UTF-8 and move the file to the destination

            # Use a StreamReader to safely load the file with its actual encoding
            Write-Output "Copying meta.txt to destination folder"
            $reader = New-Object System.IO.StreamReader("$($SourceFolder)\meta.txt", $true)  # $true = detect encoding
            $metaContent = $reader.ReadToEnd()
            $reader.Close()
            
            # Write it out as UTF-8 without BOM
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)  # $false = no BOM
            [System.IO.File]::WriteAllText("$($DestinationFolder)\meta.txt", $metaContent, $utf8NoBom)
        }
    }

    Write-Host -ForegroundColor Green "Finished"
}
catch {
    Write-Output $_
}
