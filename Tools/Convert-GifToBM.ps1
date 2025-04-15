<#
.SYNOPSIS
    Converts a .GIF into a .BM for use with Flipper Zero asset pack animations.

.DESCRIPTION
    This script takes a .gif file and converts it into a .bm file that the Flipper Zero asset pack animations require.
    Users can leverage various parameters to customize the functionality and asthetics of the animation. 
    The script is mostly self-containing but does rely on an accompanying portable ImageMagick client app for some workloads. 

.PARAMETER GifPath
    Specify the file path of the .gif file that will be converted.
    If this is not specified, an interactive file picker will be displayed.

.PARAMETER OutputFolder
    Specify the folder path where the .bm and meta file will be output to.
    If this is not specified, an interactive folder picker will be displayed.
    If the specified folder does not end with _128x64, a folder with that string appended on the end of your specified folder will be created.

.PARAMETER PreviewGif
    Specify to output a preview.gif file and automatically open it.

.PARAMETER Invert
    Inverts image colors.

.PARAMETER Monochrome
    Converts image into either solid black or solid white colors.

.PARAMETER EdgeDetection
    Highlights the boundaries and outlines within an image by detecting areas with sharp contrast like where a dark object meets a light background.
    A lower number will pick up faint edges but may make an image more noisy.
    A higher number will pick up more contrast edges and produce smoother but thicker lines.

.PARAMETER Binarization
    The threshold a pixel has to be before it becomes black or white (default: .5).
    
    Example A: At a .5 binarization, any pixel lighter than .5 becomes white.
    Any pixel darker than .5 becomes black.

    Example B: At a .8 binarization, most pixels will be lighter than the threshold so they will all be converted to white
    This results in a mostly white image.

.PARAMETER ActiveCycles
    Number of times active frames should cycle before returning to passive (default: 1).

.PARAMETER FrameRate
    Frame rate in frames per second (default: 4).

.PARAMETER Duration
    How long the animation plays before the next (default: 3600).

.PARAMETER Cooldown
    Cooldown time before active frames can trigger again (default: 5).

.PARAMETER ActiveFrames
    Number of frames that play during active mode (default: 0).

.PARAMETER BubbleLocale
    Placement of a speech bubble.

.PARAMETER BubbleText
    Text for the speech bubble. Use `n for new lines.

.PARAMETER StartFrame
    Frame index at which the speech bubble appears (default: 0).
    If you want the bubble text to show up later, increase this number.

.PARAMETER EndFrame
    Frame index at which the speech bubble disappears (default: 0).
    If you want the bubble text to end sooner, set it below the max number of frames.

.EXAMPLE
    .\gifToFlipperAsset.ps1
    Uses default settings to convert a .gif to .bm    

.EXAMPLE
    .\gifToFlipperAsset.ps1 -Verbose
    Shows verbose output on screen - useful for troubleshooting

.EXAMPLE
    .\gifToFlipperAsset.ps1 -Invert $true -Dither $false -SharpenAmount "2x2"
    Applies image inversion, disables dithering, and uses stronger sharpening.

.EXAMPLE
    .\gifToFlipperAsset.ps1 -BubbleLocale "bottomright" -BubbleText "Hello Flipper!"
    Places a speech bubble in the bottom-right corner. The text is on a single line and lasts the entire animation since no start and end frame were specified.
.EXAMPLE
    .\gifToFlipperAsset.ps1 -BubbleLocale "bottomright" -BubbleText "Hello\nFlipper!" -StartFrame 3 -EndFrame 7
    Places a speech bubble in the bottom-right corner visible from frame 3 to 7.
    the words Hello and Flipper! are on two separate lines due to the use of \n between the two words

.NOTES
    Author: 5mendo4
    Requires: PowerShell 5.1 or higher, portable magick.exe in the same folder as this script.
#>

[CmdletBinding()]

param (
    # === Interactive Parameters ===
    [string]$GifPath,
    [string]$OutputFolder,
    [switch]$PreviewGif,

    # === Effect Parameters ===
    [switch]$Invert,
    [switch]$Monochrome,
    [int]$EdgeDetection,
    [validateset(.1,.2,.3,.4,.5,.6,.7,.8,.9)]
    [double]$Binarization = .5,
    
    # === Functional Parameters ===
    [int]$ActiveCycles = 1,
    [int]$FrameRate = 4,
    [int]$Duration = 3600,
    [int]$Cooldown = 5,
    [int]$ActiveFrames = 0,

    # === Speech Bubble Parameters ===
    [ValidateSet("center", "bottomcenter", "topcenter", "leftcenter", "rightcenter", "bottomright", "topright", "bottomleft", "topleft")]
    [string]$BubbleLocale = "",
    [string]$BubbleText = "",
    [int]$StartFrame = 0,
    [int]$EndFrame = 0
)

# Check minimum PowerShell version (e.g., 5.1 required)
Write-Verbose "Validating current PS version meets minimum requirements"
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Error "This script requires PowerShell 5.1 or higher. Your version: $($PSVersionTable.PSVersion)"
    exit
}

if (!$GifPath -or !$OutputFolder) {
    # Add required assembly for windows form and dialog boxes
    Write-Verbose "Adding required .net assemblies"
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create a top-most dummy form to use as a parent window
    $topForm = New-Object System.Windows.Forms.Form
    $topForm.TopMost = $true
    $topForm.WindowState = 'Minimized'
    $topForm.ShowInTaskbar = $false
    $null = $topForm.Show()

    if (!$GifPath) {
        # Open File Dialog for GIF selection
        Write-Verbose "Prompting user for file selection"
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "GIF files (*.gif)|*.gif"
        $openFileDialog.Title = "Select a GIF to convert"
        if ($openFileDialog.ShowDialog($topForm) -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Error "No GIF selected. Exiting."
            $topForm.Close()
            exit
        }
        $GifPath = $openFileDialog.FileName
    }
    else {
        if (Test-Path $GifPath) {
            $WorkingDir = Split-Path $GifPath
        }
        else {
            Write-Error "Specified GifPath file not found"
            exit
        }
    }

    if (!$OutputFolder) {
        # Open Folder Dialog for Output selection
        Write-Verbose "Prompting user for folder save location"
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Select the output folder for the Flipper Asset Pack"
        $folderBrowser.SelectedPath = [System.IO.Path]::GetDirectoryName($GifPath)  # Set default to GIF's folder
        if ($folderBrowser.ShowDialog($topForm) -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Error "No output folder selected. Exiting."
            $topForm.Close()
            exit
        }
        $selectedFolder = $folderBrowser.SelectedPath
    }
    else {
        if (Test-Path $OutputFolder) {
            $selectedFolder = $OutputFolder
        }
        else {
            Write-Error "Specified OutputFolder directory not found"
            exit
        }
    }

    # Cleanup the dummy form
    $topForm.Close()
}

Write-Host "Processing..."

# Sanitize and format the output folder name
Write-Verbose "Sanitizing output folder name"
$folderName = [System.IO.Path]::GetFileName($selectedFolder)
$parentPath = [System.IO.Path]::GetDirectoryName($selectedFolder)
$sanitizedFolderName = ($folderName -replace '\s+', '_')
if (-not $sanitizedFolderName.EndsWith("128x64")) {
    $sanitizedFolderName += "_128x64"
}
$OutputFolder = Join-Path $parentPath $sanitizedFolderName

$ErrorActionPreference = 'Stop'

try {
    Write-Verbose "Creating output folder: $OutputFolder"
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder | Out-Null
    }

    Write-Verbose "Validating magick.exe client app exists"
    $magick = Join-Path $PSScriptRoot "magick.exe"
    if (-not (Test-Path $magick)) {
        Write-Error "magick.exe not found in script folder. Please include portable ImageMagick (magick.exe in the same folder as this script)."
        exit
    }

    Write-Verbose "Validating mkbitmap.exe client app exists"
    $mkbitmap = Join-Path $PSScriptRoot "mkbitmap.exe"
    if (-not (Test-Path $mkbitmap)) {
        Write-Error "mkbitmap.exe not found in script folder. Please include portable mkbitmap (mkbitmap.exe in the same folder as this script)."
        exit
    }

    Write-Verbose "Validating potrace.exe client app exists"
    $potrace = Join-Path $PSScriptRoot "potrace.exe"
    if (-not (Test-Path $potrace)) {
        Write-Error "potrace.exe not found in script folder. Please include portable potrace (potrace.exe in the same folder as this script)."
        exit
    }

    Write-Verbose "Splitting and converting .gif into .png frames..."

    & $magick $GifPath -coalesce "$(Join-Path $WorkingDir "frame_%d.pbm")"

    # Step 2: Process PNGs into .bm files
    $pngFiles = Get-ChildItem -Path $WorkingDir -Filter "frame_*.pbm" | Sort-Object Name
    $index = 0
    $FrameOrder = ""

    Write-Verbose "Processing png files"
    foreach ($file in $pngFiles) {
        $PGMFile = "$WorkingDir\frame_$($index).pgm"
        $PBMFile = "$WorkingDir\frame_$($index).pbm"
        $PNGFile = "$WorkingDir\frame_$($index).png"
        $SVGFile = "$WorkingDir\frame_$($index).svg"
        $PreviewFile = "$WorkingDir\preview_$($index).png"
        $BMFile = "$OutputFolder\frame_$($index).bm"
        
        Write-Verbose "Converting .png into .svg vector graphic using potrace"
        & $Potrace "$($file.FullName)" -b svg -o "$SVGFile"

        Write-Verbose "Applying immage effects using ImageMagick"
        $MagickArgs = @(
            "$SVGFile",
            "-sharpen","2x1",
            "-colorspace","gray",
            "$PGMFile"
        )

        & $magick @MagickArgs
    
        Write-Verbose "Using mkbitmap to apply image effects and conver to .pgm"
        & $Mkbitmap -x -t $Binarization -o "$PBMFile" "$PGMFile"
    
        Write-Verbose "Using ImageMagick to crop and resize .pbm back to .png file"
        $MagickArgs = @(
            "$PBMFile",
            $(if ($EdgeDetection) {@("-edge","$EdgeDetection")})
            "$(if ($Invert) {"-negate"})"
            "$(if ($Monochrome) {"-monochrome"})"
            "-resize","128x64",
            "-gravity","center",
            "-extent","128x64",
            "$PNGFile"
        )

        & $magick @MagickArgs

        Write-Verbose "Coverting .png to .bm flipper file"
        $bitmap = [System.Drawing.Bitmap]::FromFile("$PNGFile")

        $width = $bitmap.Width
        $height = $bitmap.Height
        $rawBytes = New-Object System.Collections.Generic.List[Byte]
        
        for ($y = 0; $y -lt $height; $y++) {
            $bitBuffer = 0
            $bitCount = 0
        
            for ($x = 0; $x -lt $width; $x++) {
                $color = $bitmap.GetPixel($x, $y)
                $bit = if ($color.R -eq 0) { 0 } else { 1 }
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
        
        # Finalize .bm with 0x00 header
        $finalBytes = New-Object System.Collections.Generic.List[Byte]
        $finalBytes.Add(0x00)
        $finalBytes.AddRange($rawBytes)
        [System.IO.File]::WriteAllBytes($BMFile, $finalBytes.ToArray())
        
        # Invert colors if user wants a preview gif
        if ($PreviewGif) {    
            & $magick "$PNGFile" -negate "$PreviewFile"
        }

        $FrameOrder += "$index "
        $index++
        # Cleanup
        $bitmap.Dispose()
    }

    # Step 3: Generate meta.txt
    Write-Verbose "Formulating the meta file"
    $FrameOrder = $FrameOrder.TrimEnd()
    $MetaContent = @"
Filetype: Flipper Animation
Version: 1

Width: 128
Height: 64
Passive frames: $index
Active frames: $ActiveFrames
Frames order: $FrameOrder
Active cycles: $ActiveCycles
Frame rate: $FrameRate
Duration: $Duration
Active cooldown: $Cooldown

Bubble slots: $([int]($BubbleText -ne ""))
"@

    # Ensure the meta.txt file is utf-8 encoded
    Write-Verbose "Enconding meta file"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText((Join-Path $OutputFolder "meta.txt"), $MetaContent, $utf8NoBom)

    # Append bubble configuration if provided
    if ($BubbleText -ne "") {
        Write-Verbose "Formulating bubble info in meta file"
        if ($StartFrame -eq 0 -and $EndFrame -eq 0) {
            $StartFrame = 0
            $EndFrame = $index
        }
        switch ($BubbleLocale.ToLower()) {
            "center"        { $BubbleX = 64;  $BubbleY = 32;  $AlignH = "Center"; $AlignV = "Bottom" }
            "bottomcenter"  { $BubbleX = 64;  $BubbleY = 49;  $AlignH = "Center"; $AlignV = "Top" }
            "topcenter"     { $BubbleX = 64;  $BubbleY = 0;  $AlignH = "Center"; $AlignV = "Bottom" }
            "leftcenter"    { $BubbleX = 0;  $BubbleY = 32;  $AlignH = "Right";  $AlignV = "Center" }
            "rightcenter"   { $BubbleX = 115; $BubbleY = 32;  $AlignH = "Left";   $AlignV = "Center" }
            "bottomright"   { $BubbleX = 115; $BubbleY = 49;  $AlignH = "Left";   $AlignV = "Top" }
            "topright"      { $BubbleX = 115; $BubbleY = 0;  $AlignH = "Left";   $AlignV = "Bottom" }
            "bottomleft"    { $BubbleX = 0;  $BubbleY = 49;  $AlignH = "Right";  $AlignV = "Top" }
            "topleft"       { $BubbleX = 0;  $BubbleY = 0;  $AlignH = "Right";  $AlignV = "Bottom" }
            default          { $BubbleX = 64;  $BubbleY = 32;  $AlignH = "Center"; $AlignV = "Bottom" }
        }

        # Dynamically shift bubble based on number of lines user specified via \n
        # For every line a user adds, we need to move the bubble up 12 pixels or reduce the bubbley value by 12
        # We also need to ensure bubbley never gets less than 0
        $lineCount = ($BubbleText -split '\\n').Count
        if ($lineCount -gt 1) {
            $verticalOffset = 12 * ($lineCount - 1)
            $BubbleY = [math]::Max(0, $BubbleY - $verticalOffset)
        }

        # Dynamically shift bubble based on number of characters user specified
        # For every character a user adds, we need to move the bubble left 5 pixels or reduce the bubblex value by 5
        # We also need to ensure bubblex never gets less than 0
        $characterCount = ($BubbleText -replace '\\n', '').Length
        if ($characterCount -gt 1) {
            $horizontalOffset = 6 * ($characterCount - 1)
            $Bubblex = [math]::Max(0, $Bubblex - $horizontalOffset)
        }

        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "`nSlot: 0"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "X: $BubbleX"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "Y: $BubbleY"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "Text: $BubbleText"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "AlignH: $AlignH"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "AlignV: $AlignV"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "StartFrame: $StartFrame"
        Add-Content -Path (Join-Path $OutputFolder "meta.txt") -Value "EndFrame: $EndFrame"
    }

    if ($PreviewGif) {
        # Make Sample gif
        Write-Verbose "Making preview gif"
        $FrameFiles = Get-ChildItem -Path $WorkingDir -Filter "preview_*.png" | Sort-Object | ForEach-Object {$_.fullname}
        #& $magick -delay 25 -loop 0 "$($FrameFiles.FullName)" "$WorkingDir\preview.gif"
        $gifArgs = @('-delay', '25', '-loop', '0') + $FrameFiles + "$WorkingDir\preview.gif"
        & $magick @gifArgs

        ."$WorkingDir\preview.gif"
        #Get-ChildItem -Path $WorkingDir -Filter preview_* | Remove-Item -Force
    }

    # Cleanup
    Get-ChildItem -Path $WorkingDir -Filter frame_* | Remove-Item -Force

    Write-Host -ForegroundColor Green "Asset pack successfully created in: $OutputFolder"
}
catch {
    Write-Error $_
}
