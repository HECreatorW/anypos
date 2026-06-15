# Builds a single self-contained index.html by inlining all local CSS and JS.
# After running, index.html needs NO css/ or js/ folder — upload that one file.
# Source of truth stays in css/ and js/. Re-run after restoring the modular
# index.html if you change the sources.
$root = $PSScriptRoot
# Read as UTF-8 so emojis (☕👥📢) and em-dashes survive the build.
$html = Get-Content (Join-Path $root 'index.html') -Raw -Encoding UTF8

$base   = Get-Content (Join-Path $root 'css/base.css') -Raw -Encoding UTF8
$themes = Get-Content (Join-Path $root 'css/themes.css') -Raw -Encoding UTF8
$style  = "<style>`n$base`n$themes`n</style>"

$html = $html.Replace('<link rel="stylesheet" href="css/base.css" />', $style)
$html = $html.Replace('<link rel="stylesheet" href="css/themes.css" />', '')

$jsFiles = @('config','util','auth','friends','chat','groups','settings','developer','app')
foreach ($f in $jsFiles) {
  $code = Get-Content (Join-Path $root "js/$f.js") -Raw -Encoding UTF8
  $tag  = "<script src=""js/$f.js""></script>"
  $html = $html.Replace($tag, "<script>`n$code`n</script>")
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $root 'index.html'), $html, $enc)
Write-Host "Built self-contained index.html ($([math]::Round((Get-Item (Join-Path $root 'index.html')).Length/1KB,1)) KB)" -ForegroundColor Green
