# Builds a single self-contained index.html by inlining all local CSS and JS.
# Template = index.src.html (with css/ + js/ refs). Output = index.html (inlined).
# Edit sources in index.src.html, css/, js/, then run ./build.ps1 to regenerate.
# Upload only the generated index.html to GitHub.
$root = $PSScriptRoot
# Read as UTF-8 so emojis (☕👥📢) and em-dashes survive the build.
$html = Get-Content (Join-Path $root 'index.src.html') -Raw -Encoding UTF8

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
