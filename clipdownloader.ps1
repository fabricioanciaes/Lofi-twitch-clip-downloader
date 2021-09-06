$errors = 0

Write-Host "======================================================="
Write-Host "Lofi twitch clip downloader"
Write-Host "======================================================="

If(!(test-path './clips'))
{
      New-Item -ItemType Directory -Force -Path './clips' | Out-Null
}

If(!(test-path './output'))
{
      New-Item -ItemType Directory -Force -Path './output' | Out-Null
}

if (!(Test-Path "./settings.ini"))
{
   New-Item -path ./ -name settings.ini -type "file" -value '[Auth]
CLIENT_ID=""
CLIENT_SECRET=""
   
[OPTIONS]
fontFile="Tahoma-Bold"
authorPrefix="Clipe por\:"
fontSize="48"
fontColor="ffffff"
borderColor="000000"
borderThickness="7"
fadeInStartTime="0"
fadeInDuration="0.25"
textDisplayTime="5"
fadeOutDuration="0.3"
xPosition="10"
yPosition="h-th-10"' | Out-Null
}

if (!(Test-Path "./cliplist.txt"))
{
    New-Item -path ./ -name cliplist.txt -type "file" | Out-Null
    Write-Host '========================================='
    Write-Host "Please edit the cliplist.txt with twitch clips urls"
    Write-Host "Add one clip url per line"
    Write-Host "Examples:"
    Write-Host "https://clips.twitch.tv/AmazonianBitterCroquettePrimeMe--s5TkNBC2QVkValD"
    Write-Host "https://www.twitch.tv/mizuyong/clip/SincereWealthySheepHeyGirl-twqzjrZImj3orBs6?filter=clips&range=7d&sort=time"
    Write-Host "RepleteGrotesqueSandpiperMoreCowbell-PXjLOy0xtQKV0E3I"
    Write-Host '========================================='
    $errors = 1
}

$INI = Get-Content ./settings.ini

$config = @{}
$IniTemp = @()
ForEach($Line in $INI)
{
If ($Line -ne "" -and $Line.StartsWith("[") -ne $True)
{
$IniTemp += $Line
}
}
ForEach($Line in $IniTemp)
{
$SplitArray = $Line.Split("=")
$config += @{$SplitArray[0] = $SplitArray[1] -replace '"', ""}
}

$CLIENT_ID = [string]$config.CLIENT_ID
$CLIENT_SECRET = [string]$config.CLIENT_SECRET

if(!$config.CLIENT_ID -or !$config.CLIENT_SECRET) {
    Write-Host '========================================='
    Write-Host 'Please add your CLIENT_ID and CLIENT_SECRET to settings.ini'
    Write-Host 'Check https://dev.twitch.tv/docs/api/#step-1-register-an-application'  
    Write-Host 'for more info on how to get your tokens'
    Write-Host '========================================='
    $errors = 1
}

if($errors -eq 1) {
    Exit
}

$ACCESS_TOKEN = (Invoke-RestMethod -Uri "https://id.twitch.tv/oauth2/token?client_id=$($CLIENT_ID)&client_secret=$($CLIENT_SECRET)&grant_type=client_credentials" -Method POST).access_token

function Get-ClipIds {
    $clipIds = @()
    foreach($line in Get-Content ./cliplist.txt) {
        [uri]$URL = $line
        $domain = $url.Authority -replace '^www\.'
    
        switch($domain) {
            "clips.twitch.tv" {$clipIds +=$URL.LocalPath.split('/')[1]}
            "twitch.tv" {$clipIds += $URL.LocalPath.split('/')[3]}
            default {$clipIds += $line}
        }   
    }
    return $clipIds
}

function Remove-StringDiacritic {
    <#
.SYNOPSIS
    This function will remove the diacritics (accents) characters from a string.
.DESCRIPTION
    This function will remove the diacritics (accents) characters from a string.
.PARAMETER String
    Specifies the String(s) on which the diacritics need to be removed
.PARAMETER NormalizationForm
    Specifies the normalization form to use
    https://msdn.microsoft.com/en-us/library/system.text.normalizationform(v=vs.110).aspx
.EXAMPLE
    PS C:\> Remove-StringDiacritic "L'été de Raphaël"
    L'ete de Raphael
.NOTES
    Francois-Xavier Cat
    @lazywinadmin
    lazywinadmin.com
    github.com/lazywinadmin
#>
    [CMdletBinding()]
    PARAM
    (
        [ValidateNotNullOrEmpty()]
        [Alias('Text')]
        [System.String[]]$String,
        [System.Text.NormalizationForm]$NormalizationForm = "FormD"
    )

    FOREACH ($StringValue in $String) {
        Write-Verbose -Message "$StringValue"
        try {
            # Normalize the String
            $Normalized = $StringValue.Normalize($NormalizationForm)
            $NewString = New-Object -TypeName System.Text.StringBuilder

            # Convert the String to CharArray
            $normalized.ToCharArray() |
                ForEach-Object -Process {
                    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($psitem) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                        [void]$NewString.Append($psitem)
                    }
                }

            #Combine the new string chars
            Write-Output $($NewString -as [string])
        }
        Catch {
            Write-Error -Message $Error[0].Exception.Message
        }
    }
}
Function Remove-InvalidFileNameChars {
    param(
      [Parameter(Mandatory=$true,
        Position=0,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
      [String]$Name
    )
  
    $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
    $re = "[{0}]" -f [RegEx]::Escape($invalidChars)
    $stripedString = ($Name -replace $re)
    return Remove-StringDiacritic $stripedString
  }
function Get-Clip {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $clipId
    )

    [uri]$url = "https://api.twitch.tv/helix/clips?id=$($clipId)"
    $headers = @{
        "Authorization" = "Bearer " + "$ACCESS_TOKEN";
        "Client-ID" = $CLIENT_ID
    }

    $response = (Invoke-RestMethod -Uri $url -Headers $headers)

    $creator_name = $response.data[0].creator_name
    $title = Remove-InvalidFileNameChars $response.data[0].title
    $filename = Remove-InvalidFileNameChars "($($creator_name)) $($title)"
    $download = ($response.data[0].thumbnail_url -split '-preview-')[0] + '.mp4'

    Invoke-WebRequest -Uri $download -OutFile "$($PSScriptRoot)\clips\$($filename + '.mp4')"
    Write-Host "[Downloaded] $($creator_name) - $($title)"
}

function Write-Videos {
    $videos = Get-ChildItem "$($PSScriptRoot)/clips"

    if($videos.length -ge 1) {
        forEach ($file in $videos) {
            $file.Name -match '^\(([^)]*)\)'
            $author = $Matches[1]
    
            $fontFile = $config.fontFile
            $authorPrefix = $config.authorPrefix
            $fontSize = $config.fontSize
            $fontColor = $config.fontColor
            $borderColor = $config.borderColor
            $borderThickness = [decimal]$config.borderThickness
            $fadeInStartTime = [decimal]$config.fadeInStartTime
            $fadeInDuration = [decimal]$config.fadeInDuration
            $textDisplayTime = [decimal]$config.textDisplayTime
            $fadeOutDuration = [decimal]$config.fadeOutDuration
            $xPosition =  $config.xPosition 
            $yPosition =  $config.yPosition 
    
            [decimal]$fadeOutTime = $fadeInStartTime + $fadeInDuration + $textDisplayTime;
    
            $filterString = "[0:v]drawtext=fontfile='$($fontFile)':text='$($authorPrefix) $($author)':fontsize=$($fontSize):fontcolor=$($fontColor):alpha='if(lt(t,$($fadeInStartTime)),0,if(lt(t,$($fadeInStartTime + $fadeInDuration)),(t-$($fadeInStartTime))/$($fadeInDuration),if(lt(t,$($fadeInStartTime + $fadeInDuration + $textDisplayTime)),1,if(lt(t,$($fadeInStartTime + $fadeInDuration + $textDisplayTime + $fadeOutDuration)),($($fadeOutDuration)-(t-$($fadeOutTime)))/$($fadeOutDuration),0))))':x=$($xPosition):y=$($yPosition):bordercolor=$($borderColor):borderw=$($borderThickness)"
    
            .\ffmpeg.exe -y -i "./clips/$($file.Name)" -filter_complex $filterString -c:a copy "./output/$($file.Name)"
        }
    }
}
$clips = Get-ClipIds

if($clips.length -ge 1) {
    forEach ($clip in $clips) {
        Get-Clip($clip)
    }
} else {
    Write-Host '========================================='
    Write-Host 'Please add clips to cliplist.txt'
    Write-Host '========================================='
    Exit
}

Write-Videos