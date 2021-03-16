<#
  .SYNOPSIS
  Starts a Trace recording session enabling V8 TraceLogging provider.

  .DESCRIPTION
  Starts a Trace recording session enabling V8 TraceLogging provider.

  .PARAMETER IncludeInspectorTraces
  Include this switch if the session should record inspector traffic.

  .PARAMETER Chatty
  Include this switch if the session should record verbose traces.

  .PARAMETER SessionName
  Include this paramter if the trace session name needs to be overriden.

  .PARAMETER RealTime
  Start realtime session and write traces to console. By default, the traces are collected to an ETL file.

  .PARAMETER RealTimeOutputToFile
  Start realtime session and write traces to a text file.

  .PARAMETER IncludeGeneralTrace
  Enable general system providers. Take effect only for non-realtime sessions.

  .PARAMETER NoAnalysis
  Start WPA with the collected traces. Take effect only for non-realtime sessions.

  .INPUTS
  None. You cannot pipe objects to this script.

  .OUTPUTS
  None. This script does not generate any output.

  .EXAMPLE
  PS> .\utils\tracing\win\Start-Tracing.ps1 -IncludeGeneralTrace

  .EXAMPLE
  PS> .\scripts\tracing\trace.ps1
  PS> .\scripts\tracing\trace.ps1 -IncludeInspectorTraces
  PS> .\scripts\tracing\trace.ps1 -RealTime
#>

[CmdletBinding()]
Param(
    [Parameter(ParameterSetName='Default', Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [switch]$IncludeInspectorTraces,
    [switch]$Chatty,
    [switch]$RealTime,
    [switch]$RealTimeOutputToFile,
    [switch]$IncludeGeneralTrace,
    [switch]$NoAnalysis,
    [String]$SessionName = 'V8TraceSession'
)

begin {
    Set-StrictMode -Version Latest
}

process {

    function Find-VS-Path() {
        $vsWhere = (get-command "vswhere.exe" -ErrorAction SilentlyContinue)
        if ($vsWhere) {
            $vsWhere = $vsWhere.Path
        }
        else {
            $vsWhere = "${Env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" 
        }
   
        if (Test-Path $vsWhere) {
            $versionJson = & $vsWhere -format json 
            $versionJson = & $vsWhere -format json -version 16
            $versionJson = $versionJson | ConvertFrom-Json 
        }
        else {
            $versionJson = @()
        }
   
        # We don't care which installation the trace tools come from.
        if ($versionJson.Length -gt 1) { Write-Warning 'More than one VS install detected, picking the first one'; $versionJson = $versionJson[0]; }
        return $versionJson.installationPath
    }

    # If not admin, restart the script as admin and forward arguments.
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))  
    {  
        $arguments = $MyInvocation.MyCommand.Definition
        
        $ParameterList = (Get-Command -Name $MyInvocation.InvocationName).Parameters;
        foreach ($key in $ParameterList.keys)
        {
            $var = Get-Variable -Name $key -ErrorAction SilentlyContinue;
            if($var)
            {
                write-host "$($var.name) > $($var.value)"
                
                # Switch
                if ($var.value -eq $True)
                {
                    $arguments = $arguments + " -$($var.name)"
                } elseif ($var.value -ne $False)
                {
                    $arguments = $arguments + " -$($var.name) $($var.value)"
                }
            }
        }

        Write-Host -NoNewLine "$arguments";
        Start-Process powershell -Verb runAs -ArgumentList $arguments

        Break
    }

    $vsInstallPath  = Find-VS-Path
    Import-Module (Join-Path $vsInstallPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
    Enter-VsDevShell -VsInstallPath $vsInstallPath -SkipAutomaticLocation

    if ($RealTime.IsPresent)
    {
        # These guids should match the TraceLog provider definition in code.
        $traceLogStartCmd = "tracelog -start $SessionName -guid #85A99459-1F1D-49BD-B3DC-E5EF2AD0C2C8 -rt"
        $traceLogEnableInspectorCmd = "tracelog -enable $SessionName -guid #5509957C-25B6-4294-B2FA-8A8E41E6BC37"
        
        if(!$RealTimeOutputToFile.IsPresent) {
            $traceLogDisplayCmd = "tracefmt -rt $SessionName -displayonly"
        } else {
            $scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
            $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss") 
            $outFileName = "trace_" + $timestamp + ".txt"
            $outFilePath = Join-Path -Path $scriptPath -ChildPath $outFileName

            $traceLogDisplayCmd = "tracefmt -rt $SessionName -o $outFilePath"
            Write-Host "Writing to $outFilePath ... \n"
        }
        
        $traceLogStopCmd = "tracelog -stop $SessionName"
        
        $traceLogCmd = $traceLogStartCmd
        if ($IncludeInspectorTraces.IsPresent)
        {
            $traceLogCmd = $traceLogCmd + " & $traceLogEnableInspectorCmd"
        }

        $traceLogCmd = $traceLogCmd + " & $traceLogDisplayCmd"
        $traceLogCmd = $traceLogCmd + " & $traceLogStopCmd"

        Write-Host $traceLogCmd
        cmd /c "$traceLogCmd & pause"

        Write-Host -NoNewLine 'Press any key to continue...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    } else {
        $scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
        $wprpPath = Join-Path -Path $scriptPath -ChildPath "trace.wprp"

        if (!(Get-Command "wpr.exe" -ErrorAction SilentlyContinue)) { 
            throw "
            ################################################################
            wpr.exe (Windows Performance Recorder) unavailable ! 
            Ensure that WPT (Windows Performance Toolkit) is installed and its tools are added to the path 
            ################################################################"
        }

        $wprArgs = "-start", $wprpPath

        if ($IncludeGeneralTrace) {
            $wprArgs += "-start", "GeneralProfile"
        }

        Write-Host "wpr.exe $wprArgs"
        & Start-Process -Verb RunAs "wpr.exe" -ArgumentList $wprArgs -PassThru -Wait


#        Write-Host -NoNewLine 'Press any key to stop the tracing sesion...';
#        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
        read-host 'Press ENTER to stop the tracing sesion...'

        $scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
        $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss") 
        $fileName = "rnw_" + $timestamp + ".etl"
        $etlPath = Join-Path -Path $scriptPath -ChildPath $fileName

        if (!(Get-Command "wpr.exe" -ErrorAction SilentlyContinue)) { 
            throw "
        ################################################################
        wpr.exe (Windows Performance Recorder) unavailable ! 
        Ensure that WPT (Windows Performance Toolkit) is installed and its tools are added to the path 
        ################################################################"
        }
        
        $wprArgs = "-stop", $etlPath

        Write-Host "wpr.exe $wprArgs"
        & Start-Process -Verb RunAs "wpr.exe" -ArgumentList $wprArgs -PassThru -Wait

        if (!(Get-Command "wpa.exe" -ErrorAction SilentlyContinue)) { 
            Write-Host "wpa.exe (Windows Performance Analyzer) unavailable !"
            Write-Host "Ensure that WPT (Windows Performance Toolkit) is installed and its tools are added to the path "
        }

        if ($NoAnalysis) {
            Write-Host "To analys this trace, install WPT and run: 'wpa $etlPath'"
        }
        else {

            if (!(Get-Command "wpa.exe" -ErrorAction SilentlyContinue)) { 
                throw "
                ################################################################
                wpa.exe (Windows Performance Analyzer) unavailable ! 
                Ensure that WPT (Windows Performance Toolkit) is installed and its tools are added to the path 
                ################################################################"
            }

            $wpaArgs = $etlPath
            Write-Host "wpa.exe $wpaArgs"
            & Start-Process -Verb RunAs "wpa.exe" -ArgumentList $wpaArgs
        }

        Write-Host -NoNewLine 'Press any key to exit ...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    }
}
