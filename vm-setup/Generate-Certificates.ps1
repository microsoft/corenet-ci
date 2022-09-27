<#

.SYNOPSIS
This generates certificates used for test signing.

#>

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$Name = "CoreNetTestSigning"
$CodeSignCertPath = "CoreNetSignRoot.cer"
$CertPath = "CoreNetSign.pfx"

# Generate the signing certificate.
Write-Host "Generating signing certificate..."
$CodeSignCert = New-SelfSignedCertificate `
    -FriendlyName $Name `
    -Subject "CN=$Name" `
    -HashAlgorithm SHA256 `
    -KeyUsage DigitalSignature `
    -KeyUsageProperty Sign `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3,1.3.6.1.4.1.311.10.3.6","2.5.29.19 = {text}") `
    -NotAfter (Get-Date).AddYears(10) `
    -KeyExportPolicy Exportable `
    -Type Custom

# Export the cert file used to trust.
Write-Host "Exporting $CodeSignCertPath file..."
Export-Certificate -Type CERT -Cert $CodeSignCert -FilePath $CodeSignCertPath
$PfxPassword = ConvertTo-SecureString -String "placeholder" -Force -AsPlainText

# Export the pfx file used for signing.
Write-Host "Exporting $CertPath file..."
Export-PfxCertificate -Cert $CodeSignCert -Password $PfxPassword -FilePath $CertPath

# Remove the temporary cert from the store.
Remove-Item $CodeSignCert.PSPath
