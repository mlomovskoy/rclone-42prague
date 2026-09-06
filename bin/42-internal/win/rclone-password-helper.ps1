# Decrypts the sibling .enc file with Windows DPAPI, which ties it to this
# Windows user account on this machine -- the same "logged in, not literally
# knows the password" tradeoff 42password makes on macOS (Keychain) and Linux
# (secret-tool). Exits 1 with no output if the file is missing, rather than
# hanging or prompting -- RCLONE_PASSWORD_COMMAND must never do either.
$encPath = Join-Path $PSScriptRoot 'rclone-password.enc'
if (-not (Test-Path -LiteralPath $encPath)) { exit 1 }
$secure = Get-Content -Raw -LiteralPath $encPath | ConvertTo-SecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
