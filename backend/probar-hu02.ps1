# Pruebas de la Guia 4 (HU-02). Correr con el backend encendido (npm run dev).
# Uso, dentro de backend:  powershell -ExecutionPolicy Bypass -File .\probar-hu02.ps1

$U = 'http://localhost:3000'
$bien = 0; $mal = 0

function Llamar($metodo, $ruta, $body = $null, $token = $null) {
  $h = @{}
  if ($token) { $h['Authorization'] = "Bearer $token" }
  $p = @{ Method = $metodo; Uri = "$U$ruta"; Headers = $h; ContentType = 'application/json' }
  if ($null -ne $body) { $p['Body'] = ($body | ConvertTo-Json) }
  try {
    $r = Invoke-RestMethod @p
    return @{ status = 200; data = $r.data; code = 'ok' }
  } catch {
    $st = [int]$_.Exception.Response.StatusCode
    $code = ''
    try { $code = ($_.ErrorDetails.Message | ConvertFrom-Json).error.code } catch {}
    return @{ status = $st; code = $code }
  }
}

function Revisar($nombre, $r, $statusEsperado, $codeEsperado = 'ok') {
  $okStatus = ($r.status -eq $statusEsperado) -or ($statusEsperado -eq 200 -and $r.status -eq 201)
  if ($okStatus -and $r.code -eq $codeEsperado) {
    Write-Host "  OK    $nombre -> $($r.status) $($r.code)" -ForegroundColor Green
    $script:bien++
  } else {
    Write-Host "  FALLA $nombre -> $($r.status) $($r.code)  (esperado $statusEsperado $codeEsperado)" -ForegroundColor Red
    $script:mal++
  }
}

Write-Host "`n== Login (HU-01) =="
$admin = Llamar POST '/auth/login' @{ correo = 'admin@crm.local'; password = 'Admin123' }
Revisar 'login admin' $admin 200
$T = $admin.data.token
Revisar 'login correo en MAYUSCULAS' (Llamar POST '/auth/login' @{ correo = 'ADMIN@crm.local'; password = 'Admin123' }) 200
Revisar 'login contrasena mala' (Llamar POST '/auth/login' @{ correo = 'admin@crm.local'; password = 'mala' }) 401 'CREDENCIALES_INVALIDAS'
Revisar 'login sin password' (Llamar POST '/auth/login' @{ correo = 'admin@crm.local' }) 400 'DATOS_FALTANTES'
Revisar 'ruta que no existe' (Llamar GET '/nada') 404 'RUTA_NO_ENCONTRADA'

Write-Host "`n== Proteccion =="
Revisar 'usuarios sin token' (Llamar GET '/usuarios') 401 'TOKEN_FALTANTE'
Revisar 'usuarios token inventado' (Llamar GET '/usuarios' $null 'hola') 401 'TOKEN_INVALIDO'
Revisar 'usuarios como admin' (Llamar GET '/usuarios' $null $T) 200
$roles = Llamar GET '/roles' $null $T
Revisar 'roles como admin' $roles 200
$rolVendedor = ($roles.data | Where-Object { $_.nombre -eq 'vendedor' }).id
Write-Host "  (id del rol vendedor: $rolVendedor)"

Write-Host "`n== Crear =="
Revisar 'crear sin datos' (Llamar POST '/usuarios' @{ nombre = 'Ana' } $T) 400 'DATOS_FALTANTES'
Revisar 'crear correo invalido' (Llamar POST '/usuarios' @{ nombre = 'Ana'; correo = 'ana'; password = 'Temporal1'; rolId = $rolVendedor } $T) 422 'CORREO_INVALIDO'
Revisar 'crear password debil' (Llamar POST '/usuarios' @{ nombre = 'Ana'; correo = 'ana@crm.local'; password = 'corta'; rolId = $rolVendedor } $T) 422 'PASSWORD_DEBIL'
Revisar 'crear rol 99' (Llamar POST '/usuarios' @{ nombre = 'Ana'; correo = 'ana@crm.local'; password = 'Temporal1'; rolId = 99 } $T) 422 'ROL_INVALIDO'
$ana = Llamar POST '/usuarios' @{ nombre = 'Ana Vendedora'; correo = 'ana@crm.local'; password = 'Temporal1'; rolId = $rolVendedor } $T
if ($ana.code -eq 'CORREO_DUPLICADO') {
  Write-Host '  (Ana ya existia de una corrida anterior, se reutiliza)'
} else {
  Revisar 'crear Ana' $ana 200
}
Revisar 'crear Ana otra vez' (Llamar POST '/usuarios' @{ nombre = 'Ana Vendedora'; correo = 'ANA@crm.local'; password = 'Temporal1'; rolId = $rolVendedor } $T) 409 'CORREO_DUPLICADO'
$lista = (Llamar GET '/usuarios' $null $T).data
$idAna = ($lista | Where-Object { $_.correo -eq 'ana@crm.local' }).id
$idAdmin = ($lista | Where-Object { $_.correo -eq 'admin@crm.local' }).id
Llamar PATCH "/usuarios/$idAna/estado" @{ activo = $true } $T | Out-Null

Write-Host "`n== Ana (vendedora) no puede entrar al modulo =="
$tokAna = (Llamar POST '/auth/login' @{ correo = 'ana@crm.local'; password = 'Temporal1' }).data.token
Revisar 'usuarios con token de Ana' (Llamar GET '/usuarios' $null $tokAna) 403 'ACCESO_DENEGADO'

Write-Host "`n== Consultar y editar =="
Revisar 'usuario 999' (Llamar GET '/usuarios/999' $null $T) 404 'USUARIO_NO_ENCONTRADO'
Revisar 'usuario abc' (Llamar GET '/usuarios/abc' $null $T) 400 'ID_INVALIDO'
Revisar "editar Ana (id $idAna)" (Llamar PUT "/usuarios/$idAna" @{ nombre = 'Ana Vendedora'; correo = 'ana@crm.local'; rolId = $rolVendedor } $T) 200
Revisar 'editar Ana con correo del admin' (Llamar PUT "/usuarios/$idAna" @{ nombre = 'Ana Vendedora'; correo = 'admin@crm.local'; rolId = $rolVendedor } $T) 409 'CORREO_DUPLICADO'
Revisar 'admin cambia su propio rol' (Llamar PUT "/usuarios/$idAdmin" @{ nombre = 'Administrador Inicial'; correo = 'admin@crm.local'; rolId = $rolVendedor } $T) 409 'AUTO_CAMBIO_ROL'

Write-Host "`n== Desactivar sin borrar =="
Revisar 'desactivar Ana' (Llamar PATCH "/usuarios/$idAna/estado" @{ activo = $false } $T) 200
Revisar 'login de Ana desactivada' (Llamar POST '/auth/login' @{ correo = 'ana@crm.local'; password = 'Temporal1' }) 401 'CREDENCIALES_INVALIDAS'
Revisar 'token viejo de Ana' (Llamar GET '/usuarios' $null $tokAna) 401 'SESION_INVALIDA'
Revisar 'admin se desactiva a si mismo' (Llamar PATCH "/usuarios/$idAdmin/estado" @{ activo = $false } $T) 409 'AUTO_DESACTIVACION'
Revisar 'activo como texto' (Llamar PATCH "/usuarios/$idAna/estado" @{ activo = 'false' } $T) 400 'ESTADO_INVALIDO'
Revisar 'reactivar Ana' (Llamar PATCH "/usuarios/$idAna/estado" @{ activo = $true } $T) 200

Write-Host "`nResultado: $bien bien, $mal mal" -ForegroundColor Cyan
Write-Host 'Ana queda activa (ana@crm.local / Temporal1): la Guia 5 la necesita.'
