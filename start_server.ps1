param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
$srcPath = Join-Path $scriptDir "src"
if (Test-Path -Path $srcPath) {
    if ($env:PYTHONPATH) {
        $env:PYTHONPATH = "{0}{1}{2}" -f $srcPath, [IO.Path]::PathSeparator, $env:PYTHONPATH
    } else {
        $env:PYTHONPATH = $srcPath
    }
}
try {
    $venvPath = Join-Path $scriptDir "venv"

    if (!(Test-Path -Path $venvPath)) {
        Write-Host "Virtual environment not found. Creating at $venvPath..."
        python -m venv $venvPath
    }

    $venvScripts = Join-Path $venvPath "Scripts"
    $activateScript = Join-Path $venvScripts "Activate.ps1"
    if (!(Test-Path -Path $activateScript)) {
        throw "Could not locate virtual environment activation script at $activateScript."
    }

    Write-Host "Activating virtual environment..."
    . $activateScript

    $requirementsPath = Join-Path $scriptDir "requirements.txt"
    if (Test-Path -Path $requirementsPath) {
        $installPrompt = Read-Host "Install or update dependencies from requirements.txt? (Y/n)"
        if ([string]::IsNullOrWhiteSpace($installPrompt) -or $installPrompt.Trim().ToLower() -eq "y") {
            Write-Host "Installing dependencies..."
            pip install -r $requirementsPath
        } else {
            Write-Host "Skipping dependency installation."
        }
    } else {
        Write-Warning "requirements.txt not found in $scriptDir. Skipping dependency installation."
    }

    function Get-DefaultValue {
        param(
            [string]$Existing,
            [string]$Fallback
        )

        if (-not [string]::IsNullOrEmpty($Existing)) {
            return $Existing
        }
        return $Fallback
    }

    function Read-ValueWithDefault {
        param(
            [string]$Prompt,
            [string]$DefaultValue
        )

        if ([string]::IsNullOrEmpty($DefaultValue)) {
            return (Read-Host $Prompt)
        }

        $response = Read-Host "$Prompt [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultValue
        }
        return $response
    }

    function Read-IntWithDefault {
        param(
            [string]$Prompt,
            [int]$DefaultValue
        )

        while ($true) {
            $response = Read-Host "$Prompt [$DefaultValue]"
            if ([string]::IsNullOrWhiteSpace($response)) {
                return $DefaultValue
            }

            $parsed = 0
            if ([int]::TryParse($response, [ref]$parsed)) {
                return $parsed
            }

            Write-Host "Please enter a valid integer value." -ForegroundColor Yellow
        }
    }

    function ConvertFrom-SecureStringToPlain {
        param(
            [System.Security.SecureString]$SecureString
        )

        if ($null -eq $SecureString) {
            return ""
        }

        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    function Read-PasswordValue {
        param(
            [string]$Prompt,
            [string]$ExistingValue
        )

        if ([string]::IsNullOrEmpty($ExistingValue)) {
            $secure = Read-Host $Prompt -AsSecureString
            return (ConvertFrom-SecureStringToPlain $secure)
        }

        $secureExistingPrompt = "$Prompt (leave blank to keep current value)"
        $secure = Read-Host $secureExistingPrompt -AsSecureString
        $value = ConvertFrom-SecureStringToPlain $secure
        if ([string]::IsNullOrEmpty($value)) {
            return $ExistingValue
        }
        return $value
    }

    $defaultHost = Get-DefaultValue $env:MYSQL_HOST "localhost"

    $defaultPort = 3306
    if (-not [string]::IsNullOrWhiteSpace($env:MYSQL_PORT)) {
        $existingPort = 0
        if ([int]::TryParse($env:MYSQL_PORT, [ref]$existingPort)) {
            $defaultPort = $existingPort
        }
    }

    $defaultUser = Get-DefaultValue $env:MYSQL_USER ""
    $defaultDatabase = Get-DefaultValue $env:MYSQL_DATABASE ""
    $existingPassword = $env:MYSQL_PASSWORD

    $mysqlHost = Read-ValueWithDefault -Prompt "MYSQL_HOST" -DefaultValue $defaultHost
    $mysqlPort = Read-IntWithDefault -Prompt "MYSQL_PORT" -DefaultValue $defaultPort
    $mysqlUser = Read-ValueWithDefault -Prompt "MYSQL_USER" -DefaultValue $defaultUser
    $mysqlDatabase = Read-ValueWithDefault -Prompt "MYSQL_DATABASE" -DefaultValue $defaultDatabase
    $mysqlPassword = Read-PasswordValue -Prompt "MYSQL_PASSWORD" -ExistingValue $existingPassword

    $env:MYSQL_HOST = $mysqlHost
    $env:MYSQL_PORT = "$mysqlPort"
    $env:MYSQL_USER = $mysqlUser
    $env:MYSQL_PASSWORD = $mysqlPassword
    $env:MYSQL_DATABASE = $mysqlDatabase

    Write-Host "Starting mysql_mcp_server with:"
    Write-Host "  MYSQL_HOST=$mysqlHost"
    Write-Host "  MYSQL_PORT=$mysqlPort"
    Write-Host "  MYSQL_USER=$mysqlUser"
    if ([string]::IsNullOrEmpty($mysqlPassword)) {
        Write-Host "  MYSQL_PASSWORD=(empty)"
    } else {
        Write-Host "  MYSQL_PASSWORD=********"
    }
    Write-Host "  MYSQL_DATABASE=$mysqlDatabase"

    Write-Host "Launching server..."
    python -m mysql_mcp_server.server
}
finally {
    Pop-Location
}
