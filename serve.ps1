# Simple static file server for Kopi Chat (Windows PowerShell)
# Usage:  ./serve.ps1   then open http://localhost:5500
param([int]$Port = 5500)
$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Kopi Chat running at http://localhost:$Port  (Ctrl+C to stop)" -ForegroundColor Green

$mime = @{
  ".html"="text/html; charset=utf-8"; ".css"="text/css; charset=utf-8"; ".js"="application/javascript; charset=utf-8";
  ".json"="application/json"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg";
  ".gif"="image/gif"; ".svg"="image/svg+xml"; ".ico"="image/x-icon"; ".woff2"="font/woff2"
}

while ($listener.IsListening) {
  $ctx = $null
  try {
    $ctx = $listener.GetContext()
    $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart("/")
    if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
    $file = Join-Path $root $path
    if (Test-Path $file -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ctx.Response.ContentLength64 = $bytes.Length
      if ($ctx.Request.HttpMethod -ne "HEAD") {
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      }
    } else {
      $ctx.Response.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
      $ctx.Response.ContentLength64 = $msg.Length
      $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
    }
  } catch {
    # Never let a single bad request kill the server loop.
    Write-Host "req error: $($_.Exception.Message)" -ForegroundColor DarkYellow
  } finally {
    if ($ctx) { try { $ctx.Response.OutputStream.Close(); $ctx.Response.Close() } catch {} }
  }
}
