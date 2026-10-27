# Pequeno servidor local para o Sete Vidas. Não precisa instalar nada.
$port = 8765
$root = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'dist')
$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript'
  '.css'  = 'text/css'
  '.json' = 'application/json'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.svg'  = 'image/svg+xml'
  '.woff' = 'font/woff'
  '.woff2' = 'font/woff2'
  '.ogg'  = 'audio/ogg'
  '.wav'  = 'audio/wav'
  '.mp3'  = 'audio/mpeg'
  '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try {
  $listener.Start()
} catch {
  Write-Host "Não consegui abrir a porta $port. Feche outra janela do Sete Vidas e tente de novo."
  Read-Host "Pressione Enter para sair"
  exit 1
}

Write-Host "Sete Vidas rodando em http://localhost:$port/"
Write-Host "Feche esta janela para encerrar o jogo."
Start-Process "http://localhost:$port/"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
    if ($rel -eq '') { $rel = 'index.html' }
    $full = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      $res.StatusCode = 404
    } else {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $type = $types[$ext]
      if (-not $type) { $type = 'application/octet-stream' }
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $res.ContentType = $type
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    }
  } catch {
    $res.StatusCode = 500
  } finally {
    $res.Close()
  }
}
