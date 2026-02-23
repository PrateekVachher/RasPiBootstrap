# Install Caddy root CA from pipi.local into Windows Trusted Root store
# Run as Administrator: powershell -ExecutionPolicy Bypass -File install-cert.ps1

$certUrl = "http://pipi.local/cert"
$certPath = "$env:TEMP\caddy-root.crt"

Write-Host "Downloading Caddy root CA from $certUrl..."
try {
    Invoke-WebRequest -Uri $certUrl -OutFile $certPath -UseBasicParsing
} catch {
    Write-Host "ERROR: Could not reach pipi.local. Make sure the Pi is running." -ForegroundColor Red
    exit 1
}

Write-Host "Installing certificate into Trusted Root Certification Authorities..."
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$store.Open("ReadWrite")
$store.Add($cert)
$store.Close()

Remove-Item $certPath -Force
Write-Host "Done! Restart your browser. https://pipi.local will now be trusted." -ForegroundColor Green
