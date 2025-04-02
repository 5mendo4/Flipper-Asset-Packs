# GifToFlipperPack.ps1
# Author: 5mendo5
# Description: Converts a .gif into a Flipper-compatible asset pack (monochrome .bm files + meta.txt)

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$GifPath,
    [Parameter(Mandatory=$true)][string]$OutputFolder,
    [Parameter()][int]$FrameRate = 4,
    [Parameter()][int]$Duration = 3600
)

$ErrorActionPreference = 'Stop'

try {
    Write-Output "Creating output folder: $OutputFolder"
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder | Out-Null
    }

    $magick = Join-Path $PSScriptRoot "magick.exe"
    if (-not (Test-Path $magick)) {
        throw "magick.exe not found in script folder. Please include portable ImageMagick."
    }

    # Step 1: Extract and convert frames to monochrome .png
    $tempPngDir = Join-Path $OutputFolder "_temp_png"
    if (-not (Test-Path $tempPngDir)) {
        New-Item -ItemType Directory -Path $tempPngDir | Out-Null
    }

    $framePattern = Join-Path $tempPngDir "frame_%d.png"
    Write-Output "Splitting and converting .gif into monochrome .png frames..."
    & $magick $GifPath -coalesce -gravity center -extent 128x64 -resize 128x64 -colorspace Gray -monochrome $framePattern

    # Step 2: Process PNGs into .bm files
    Add-Type -AssemblyName System.Drawing
    $pngFiles = Get-ChildItem -Path $tempPngDir -Filter "frame_*.png" | Sort-Object Name
    $index = 0
    $FrameOrder = ""

    foreach ($file in $pngFiles) {
        $inputPath = $file.FullName
        $outputPath = Join-Path $OutputFolder ("frame_$index.bm")

        $bitmap = [System.Drawing.Bitmap]::FromFile($inputPath)
        $forcedBitmap = $bitmap.Clone([System.Drawing.Rectangle]::FromLTRB(0, 0, $bitmap.Width, $bitmap.Height), [System.Drawing.Imaging.PixelFormat]::Format1bppIndexed)
        $bitmap.Dispose()
        $bitmap = $forcedBitmap

        $width = $bitmap.Width
        $height = $bitmap.Height
        $rawBytes = New-Object System.Collections.Generic.List[Byte]

        for ($y = 0; $y -lt $height; $y++) {
            $bitBuffer = 0
            $bitCount = 0

            for ($x = 0; $x -lt $width; $x++) {
                $color = $bitmap.GetPixel($x, $y)
                $bit = if ($color.R -eq 0) { 1 } else { 0 }
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

        $finalBytes = New-Object System.Collections.Generic.List[Byte]
        $finalBytes.Add(0x00)
        $finalBytes.AddRange($rawBytes)
        [System.IO.File]::WriteAllBytes($outputPath, $finalBytes.ToArray())

        Write-Output "Created: frame_$index.bm"
        $FrameOrder += "$index "
        $index++
        $bitmap.Dispose()
    }

    # Step 3: Generate meta.txt
    $FrameOrder = $FrameOrder.TrimEnd()
    $MetaContent = @"
Filetype: Flipper Animation
Version: 1

Width: 128
Height: 64
Passive frames: $index
Active frames: 0
Frames order: $FrameOrder
Active cycles: 1
Frame rate: $FrameRate
Duration: $Duration
Active cooldown: 5

Bubble slots: 0
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $OutputFolder "meta.txt"), $MetaContent, $utf8NoBom)

    # Optional cleanup
    Remove-Item -Path $tempPngDir -Recurse -Force

    Write-Host -ForegroundColor Green "Asset pack successfully created in: $OutputFolder"
}
catch {
    Write-Error $_
}
