param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePath
)

Add-Type -AssemblyName System.Drawing

$sourcePath = $SourcePath
$projectRoot = Split-Path -Parent $PSScriptRoot
$assetsPath = Join-Path $projectRoot 'assets'
$windowsIconPath = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
$assetIconPath = Join-Path $assetsPath 'todolist.ico'
$androidRoot = Join-Path $projectRoot 'android\app\src\main\res'

if (-not (Test-Path -LiteralPath $sourcePath)) {
  throw "找不到图标源文件：$sourcePath"
}

function New-TransparentLogo {
  param([string]$Path)

  $input = [System.Drawing.Bitmap]::FromFile($Path)
  $bitmap = New-Object System.Drawing.Bitmap($input.Width, $input.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.DrawImage($input, 0, 0, $input.Width, $input.Height)
  $graphics.Dispose()
  $input.Dispose()

  $width = $bitmap.Width
  $height = $bitmap.Height
  $left = 96.0
  $right = 928.0
  $top = 74.0
  $bottom = 944.0
  $radius = 230.0

  for ($y = 0; $y -lt $height; $y++) {
    for ($x = 0; $x -lt $width; $x++) {
      $inside = $false
      if (($x -ge ($left + $radius) -and $x -le ($right - $radius)) -or
          ($y -ge ($top + $radius) -and $y -le ($bottom - $radius))) {
        $inside = $x -ge $left -and $x -le $right -and $y -ge $top -and $y -le $bottom
      } else {
        $cornerX = if ($x -lt ($left + $radius)) { $left + $radius } else { $right - $radius }
        $cornerY = if ($y -lt ($top + $radius)) { $top + $radius } else { $bottom - $radius }
        $distance = [Math]::Sqrt([Math]::Pow($x - $cornerX, 2) + [Math]::Pow($y - $cornerY, 2))
        $inside = $distance -le $radius
      }
      if (-not $inside) {
        $bitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
      }
    }
  }

  New-Item -ItemType Directory -Force -Path $assetsPath | Out-Null
  $bitmap.Save((Join-Path $assetsPath 'todolist.png'), [System.Drawing.Imaging.ImageFormat]::Png)
  return $bitmap
}

function Save-PngSize {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [string]$Path,
    [int]$Size
  )

  $scaled = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($scaled)
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.DrawImage($Bitmap, 0, 0, $Size, $Size)
  $graphics.Dispose()
  $scaled.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  return $scaled
}

function New-Ico {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [string]$Path
  )

  $sizes = @(16, 24, 32, 48, 64, 128, 256)
  $images = @()
  foreach ($size in $sizes) {
    $scaled = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($scaled)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($Bitmap, 0, 0, $size, $size)
    $graphics.Dispose()
    $stream = New-Object System.IO.MemoryStream
    $scaled.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $images += ,@($size, $stream.ToArray(), $scaled, $stream)
  }

  $headerSize = 6
  $directorySize = 16 * $images.Count
  $offset = $headerSize + $directorySize
  $output = New-Object System.IO.MemoryStream
  $writer = New-Object System.IO.BinaryWriter($output)
  $writer.Write([UInt16]0)
  $writer.Write([UInt16]1)
  $writer.Write([UInt16]$images.Count)
  foreach ($image in $images) {
    $size = $image[0]
    $bytes = $image[1]
    $writer.Write([Byte]($(if ($size -ge 256) { 0 } else { $size })))
    $writer.Write([Byte]$(if ($size -ge 256) { 0 } else { $size }))
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$bytes.Length)
    $writer.Write([UInt32]$offset)
    $offset += $bytes.Length
  }
  foreach ($image in $images) { $writer.Write($image[1]) }
  [System.IO.File]::WriteAllBytes($Path, $output.ToArray())
  $writer.Dispose()
  $output.Dispose()
  foreach ($image in $images) { $image[2].Dispose(); $image[3].Dispose() }
}

$logo = New-TransparentLogo $sourcePath
New-Item -ItemType Directory -Force -Path (Split-Path $windowsIconPath) | Out-Null
New-Ico -Bitmap $logo -Path $assetIconPath
Copy-Item -LiteralPath $assetIconPath -Destination $windowsIconPath -Force

$androidSizes = @{
  'mipmap-mdpi' = 48
  'mipmap-hdpi' = 72
  'mipmap-xhdpi' = 96
  'mipmap-xxhdpi' = 144
  'mipmap-xxxhdpi' = 192
}
foreach ($density in $androidSizes.Keys) {
  $directory = Join-Path $androidRoot $density
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $scaled = Save-PngSize -Bitmap $logo -Path (Join-Path $directory 'ic_launcher.png') -Size $androidSizes[$density]
  $scaled.Dispose()
}
$logo.Dispose()

Write-Output '图标资源已生成。'
