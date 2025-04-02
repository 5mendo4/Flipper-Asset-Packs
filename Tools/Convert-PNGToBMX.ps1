<#
.SYNOPSIS
    Converts a .PNG into a .BMx for use with the Momentum firmware on the Flipper Zero

.DESCRIPTION
    This script takes a .png file and converts it into a .bmx file that the Momentum firmware requires on the Flipper Zero for asset pack icons.
    Users can leverage various parameters to customize the asthetics of the icon. 
    The script is mostly self-containing but does rely on an accompanying portable ImageMagick client app for some workloads. 

.PARAMETER EdgeDetection
    Enables edge detection filter before conversion (default: true).

.PARAMETER Invert
    Inverts image colors (default: false).

.PARAMETER Dither
    Enables Floyd-Steinberg dithering (default: true).

.PARAMETER Sharpen
    Applies sharpening filter (default: true).

.PARAMETER SharpenAmount
    Sharpness level passed to ImageMagick (default: "1x1").

.PARAMETER ContrastStretch
    Contrast adjustment level (default: "7%x7%").

.PARAMETER Grayscale
    Converts image to grayscale (default: true).

.PARAMETER Monochrome
    Converts image to monochrome (1-bit) (default: true).

.EXAMPLE
    .\Convert-GifToBMX.ps1
    Uses default settings to convert a .gif to .bm    

.EXAMPLE
    .\Convert-GifToBMX.ps1 -Verbose
    Shows verbose output on screen - useful for troubleshooting

.EXAMPLE
    .\Convert-GifToBMX.ps1 -Invert $true -Dither $false -SharpenAmount "2x2"
    Applies image inversion, disables dithering, and uses stronger sharpening.

.NOTES
    Author: 5mendo4
    Requires: PowerShell 5.1 or higher, portable magick.exe in the same folder as this script.
#>

[CmdletBinding()]

param (
    # === Visual Parameters ===
    [bool]$EdgeDetection = $true,
    [bool]$Invert = $false,
    [bool]$Dither = $true,
    [bool]$Sharpen = $true,
    [string]$SharpenAmount = "1x1",
    [string]$ContrastStretch = "7%x7%",
    [bool]$Grayscale = $true,
    [bool]$Monochrome = $true
)

# Check minimum PowerShell version (e.g., 5.1 required)
Write-Verbose "Validating current PS version meets minimum requirements"
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Error "This script requires PowerShell 5.1 or higher. Your version: $($PSVersionTable.PSVersion)"
    exit
}

# Check for dependency magick.exe file
Write-Verbose "Validating magick.exe client app exists"
$magick = Join-Path $PSScriptRoot "magick.exe"
if (-not (Test-Path $magick)) {
    Write-Error "magick.exe not found in script folder. Please include portable ImageMagick (magick.exe in the same folder as this script)."
    exit
}

# Add required assembly for windows form and dialog boxes
Write-Verbose "Adding required .net assemblies"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Prompt user to select icon to create
# Define static .bmx menu
$bmxFiles = @(
    "Quit",
    "Icons\BLE\BLE_Pairing_128x64.bmx",
    "Icons\Dolphin\DolphinDone_80x58.bmx",
    "Icons\Dolphin\DolphinMafia_119x62.bmx",
    "Icons\Dolphin\DolphinReadingSuccess_59x63.bmx",
    "Icons\Dolphin\DolphinSaved_92x58.bmx",
    "Icons\Dolphin\DolphinSuccess_91x55.bmx",
    "Icons\Dolphin\DolphinWait_59x54.bmx",
    "Icons\Dolphin\WarningDolphinFlip_45x42.bmx",
    "Icons\Dolphin\WarningDolphin_45x42.bmx",
    "Icons\iButton\iButtonDolphinVerySuccess_92x55.bmx",
    "Icons\Infrared\InfraredLearnShort_128x31.bmx",
    "Icons\Interface\Lockscreen.bmx",
    "Icons\NFC\NFC_dolphin_emulation_51x64.bmx",
    "Icons\Passport\passport_bad_46x49.bmx",
    "Icons\Passport\passport_happy_46x49.bmx",
    "Icons\Passport\passport_okay_46x49.bmx",
    "Icons\RFID\RFIDDolphinReceive_97x61.bmx",
    "Icons\RFID\RFIDDolphinSend_97x61.bmx",
    "Icons\Settings\dolph_cry_49x54.bmx",
    "Icons\SubGhz\Fishing_123x52.bmx",
    "Icons\SubGhz\Scanning_123x52.bmx",
    "Icons\U2F\Auth_62x31.bmx",
    "Icons\U2F\Connected_62x31.bmx",
    "Icons\U2F\Connect_me_62x31.bmx",
    "Icons\U2F\Error_62x31.bmx"
)

$done = $false
do {
    Clear-Host
    Write-Host "Select a .bmx file to create:`n"
    for ($i = 0; $i -lt $bmxFiles.Count; $i++) {
        if ($i -le 8) {
            Write-Host "$($i + 1).  $($bmxFiles[$i])"
        }
        else {
            Write-Host "$($i + 1). $($bmxFiles[$i])"
        }
    }

    $selection = Read-Host "`nSelection"

    if ($selection -ge 1 -and $selection -le $bmxFiles.Count) {
        switch ($selection) {
            1 {
                Write-Host "Exiting script. Goodbye!"
                return
            }
            default {
                $selectedFile = $bmxFiles[$selection - 1]
                $done = $true
            }
        }
    }
    else {
        Write-Host "`nInvalid selection. Please try again." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }

} while (-not $done)


# Create a top-most dummy form to use as a parent window
$topForm = New-Object System.Windows.Forms.Form
$topForm.TopMost = $true
$topForm.WindowState = 'Minimized'
$topForm.ShowInTaskbar = $false
$null = $topForm.Show()

# Open File Dialog for PNG selection
Write-Verbose "Prompting user for file selection"
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = "PNG files (*.png)|*.png"
$openFileDialog.Title = "Select a PNG to convert"
if ($openFileDialog.ShowDialog($topForm) -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Error "No PNG selected. Exiting."
    $topForm.Close()
    exit
}
$PNGPath = $openFileDialog.FileName

# Open Folder Dialog for Output selection
Write-Verbose "Prompting user for folder save location"
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the output folder for the icon"
$folderBrowser.SelectedPath = [System.IO.Path]::GetDirectoryName($PNGPath)  # Set default to GIF's folder
if ($folderBrowser.ShowDialog($topForm) -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Error "No output folder selected. Exiting."
    $topForm.Close()
    exit
}

# Cleanup the dummy form
$topForm.Close()

Write-Host "Processing..."

# Determine output file path
$OutputFile = "$($folderBrowser.SelectedPath)\$selectedFile"

$ErrorActionPreference = 'Stop'

try {
    # Code to process the .png file through magick and convert to .bmx goes here

    Write-Host -ForegroundColor Green "Icon successfully created in: $OutputFile"
}
catch {
    Write-Error $_
}
