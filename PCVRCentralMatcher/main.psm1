function Ensure-TagExists
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName
    )

    $tag = $PlayniteApi.Database.Tags | Where-Object { $_.Name -eq $TagName }

    if (-not $tag)
    {
        $tag = New-Object Playnite.SDK.Models.Tag
        $tag.Name = $TagName
        $PlayniteApi.Database.Tags.Add($tag)
    }

    return $tag
}

function Normalize-GameName
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name))
    {
        return ""
    }

    return ($Name.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Get-GameCatalog
{
    $client = New-Object System.Net.WebClient
    $client.Encoding = [System.Text.Encoding]::UTF8

    $html = $client.DownloadString("https://pcvrcentral.com/games")

    $matches = [regex]::Matches(
        $html,
        '<a[^>]*href="/games/([^"]+)"[^>]*>.*?<span class="truncate">([^<]+)</span>.*?<span class="shrink-0 text-xs text-muted-foreground">([0-9]+)\s+method',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $result = @()

    foreach ($match in $matches)
    {
        $slug = $match.Groups[1].Value.Trim()
        $name = $match.Groups[2].Value.Trim()
        $methodCount = [int]$match.Groups[3].Value

        $result += [PSCustomObject]@{
            NormalizedName = Normalize-GameName -Name $name
            Name = $name
            Url = "https://pcvrcentral.com/games/$slug"
            MethodCount = $methodCount
        }
    }

    return $result
}

function Get-PCVRCentralDataDirectory
{
    $basePath = Join-Path $env:APPDATA "Playnite\ExtensionsData\PCVRCentralMatcher_Extension"

    if (-not (Test-Path $basePath))
    {
        New-Item -Path $basePath -ItemType Directory -Force | Out-Null
    }

    return $basePath
}

function Get-PCVRCentralGamelistPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Gamelist.csv"
}

function Get-PCVRCentralGamelistOldPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Gamelist_Old.csv"
}

function Get-PCVRCentralGamelistUpdatePath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Gamelist_Update.csv"
}

function Get-PCVRCentralModlistPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Modlist.csv"
}

function Get-PCVRCentralModlistOldPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Modlist_Old.csv"
}

function Get-PCVRCentralModlistUpdatePath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Modlist_Update.csv"
}

function Get-PCVRCentralTaglistPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Taglist.csv"
}

function Get-PCVRCentralTaglistOldPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Taglist_Old.csv"
}

function Get-PCVRCentralTaglistUpdatePath
{
    $dataDirectory = Get-PCVRCentralDataDirectory
    return Join-Path $dataDirectory "PCVRCentral_Taglist_Update.csv"
}

function Get-ChangedGameNormalizedNames
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$UpdateCsvPath
    )

    $result = @()

    if ([string]::IsNullOrWhiteSpace($UpdateCsvPath))
    {
        $UpdateCsvPath = Get-PCVRCentralGamelistUpdatePath
    }

    if (-not (Test-Path $UpdateCsvPath))
    {
        return @()
    }

    $items = Import-Csv -Path $UpdateCsvPath -Delimiter ';' -Encoding UTF8

    foreach ($item in $items)
    {
        $normalized = ""

        if ($item.PSObject.Properties.Name -contains "NormalizedName")
        {
            $normalized = [string]$item.NormalizedName
        }

        if ([string]::IsNullOrWhiteSpace($normalized) -and ($item.PSObject.Properties.Name -contains "Name"))
        {
            $normalized = Normalize-GameName -Name ([string]$item.Name)
        }

        if (-not [string]::IsNullOrWhiteSpace($normalized))
        {
            $result += $normalized
        }
    }

    return @($result | Select-Object -Unique)
}

function Save-PCVRCentralGamelist
{
    $catalog = Get-GameCatalog
    $outputPath = Get-PCVRCentralGamelistPath
    $oldPath = Get-PCVRCentralGamelistOldPath

    if (Test-Path $outputPath)
    {
        if (Test-Path $oldPath)
        {
            Remove-Item -Path $oldPath -Force -ErrorAction SilentlyContinue
        }

        Move-Item -Path $outputPath -Destination $oldPath -Force -ErrorAction Stop
    }

    $catalog |
        Select-Object NormalizedName, Name, Url, MethodCount |
        Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    return $outputPath
}

function Save-PCVRCentralGamelistUpdate
{
    $currentPath = Get-PCVRCentralGamelistPath
    $oldPath = Get-PCVRCentralGamelistOldPath
    $updatePath = Get-PCVRCentralGamelistUpdatePath

    if (-not (Test-Path $currentPath))
    {
        $currentPath = Save-PCVRCentralGamelist
    }

    $newItems = @()
    if (Test-Path $currentPath)
    {
        $newItems = Import-Csv -Path $currentPath -Delimiter ';' -Encoding UTF8
    }

    $oldItems = @()
    if (Test-Path $oldPath)
    {
        $oldItems = Import-Csv -Path $oldPath -Delimiter ';' -Encoding UTF8
    }

    $oldByKey = @{}
    foreach ($item in $oldItems)
    {
        $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$item.NormalizedName)) {
            [string]$item.NormalizedName
        }
        else {
            Normalize-GameName -Name ([string]$item.Name)
        }

        if ([string]::IsNullOrWhiteSpace($normalizedName))
        {
            continue
        }

        $oldByKey[$normalizedName] = [PSCustomObject]@{
            NormalizedName = $normalizedName
            Name = [string]$item.Name
            Url = [string]$item.Url
            MethodCount = if ($item.PSObject.Properties.Name -contains "MethodCount" -and -not [string]::IsNullOrWhiteSpace([string]$item.MethodCount)) { [int]$item.MethodCount } else { 0 }
        }
    }

    $allKeys = @()
    foreach ($item in $newItems)
    {
        $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$item.NormalizedName)) {
            [string]$item.NormalizedName
        }
        else {
            Normalize-GameName -Name ([string]$item.Name)
        }

        if (-not [string]::IsNullOrWhiteSpace($normalizedName))
        {
            $allKeys += $normalizedName
        }
    }

    foreach ($key in $oldByKey.Keys)
    {
        if ($allKeys -notcontains $key)
        {
            $allKeys += $key
        }
    }

    $changes = @()

    foreach ($key in ($allKeys | Sort-Object -Unique))
    {
        $newItem = $null
        foreach ($item in $newItems)
        {
            $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$item.NormalizedName)) {
                [string]$item.NormalizedName
            }
            else {
                Normalize-GameName -Name ([string]$item.Name)
            }

            if ($normalizedName -eq $key)
            {
                $newItem = $item
                break
            }
        }

        $oldItem = $null
        if ($oldByKey.ContainsKey($key))
        {
            $oldItem = $oldByKey[$key]
        }

        if (-not $oldItem -and $newItem)
        {
            $changes += [PSCustomObject]@{
                NormalizedName = $key
                Name = [string]$newItem.Name
                OldMethodCount = 0
                NewMethodCount = if ($newItem.PSObject.Properties.Name -contains "MethodCount" -and -not [string]::IsNullOrWhiteSpace([string]$newItem.MethodCount)) { [int]$newItem.MethodCount } else { 0 }
                OldUrl = ""
                NewUrl = [string]$newItem.Url
            }
            continue
        }

        if ($oldItem -and -not $newItem)
        {
            $changes += [PSCustomObject]@{
                NormalizedName = $key
                Name = [string]$oldItem.Name
                OldMethodCount = [int]$oldItem.MethodCount
                NewMethodCount = 0
                OldUrl = [string]$oldItem.Url
                NewUrl = ""
            }
            continue
        }

        if ($oldItem -and $newItem)
        {
            $oldMethodCount = [int]$oldItem.MethodCount
            $newMethodCount = if ($newItem.PSObject.Properties.Name -contains "MethodCount" -and -not [string]::IsNullOrWhiteSpace([string]$newItem.MethodCount)) { [int]$newItem.MethodCount } else { 0 }
            $oldUrl = [string]$oldItem.Url
            $newUrl = [string]$newItem.Url

            if ($oldMethodCount -ne $newMethodCount -or $oldUrl -ne $newUrl)
            {
                $changes += [PSCustomObject]@{
                    NormalizedName = $key
                    Name = [string]$newItem.Name
                    OldMethodCount = $oldMethodCount
                    NewMethodCount = $newMethodCount
                    OldUrl = $oldUrl
                    NewUrl = $newUrl
                }
            }
        }
    }

    if ($changes.Count -gt 0)
    {
        $changes |
            Select-Object NormalizedName, Name, OldMethodCount, NewMethodCount, OldUrl, NewUrl |
            Export-Csv -Path $updatePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else
    {
        [PSCustomObject]@{
            NormalizedName = ""
            Name = ""
            OldMethodCount = ""
            NewMethodCount = ""
            OldUrl = ""
            NewUrl = ""
        } |
            Select-Object NormalizedName, Name, OldMethodCount, NewMethodCount, OldUrl, NewUrl |
            Export-Csv -Path $updatePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    return $updatePath
}

function Import-PCVRCentralGamelist
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$CsvPath
    )

    if ([string]::IsNullOrWhiteSpace($CsvPath))
    {
        $CsvPath = Get-PCVRCentralGamelistPath
    }

    if (-not (Test-Path $CsvPath))
    {
        $CsvPath = Save-PCVRCentralGamelist
    }

    $items = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8

    $result = @()

    foreach ($item in $items)
    {
        $nameValue = [string]$item.Name
        $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$item.NormalizedName)) {
            [string]$item.NormalizedName
        }
        else {
            Normalize-GameName -Name $nameValue
        }

        $result += [PSCustomObject]@{
            NormalizedName = $normalizedName
            Name = $nameValue
            Url = [string]$item.Url
            MethodCount = if ($item.PSObject.Properties.Name -contains "MethodCount" -and -not [string]::IsNullOrWhiteSpace([string]$item.MethodCount)) { [int]$item.MethodCount } else { 0 }
        }
    }

    return $result
}

function Normalize-ModUrl
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url))
    {
        return $null
    }

    $normalized = $Url.Trim()
    $normalized = $normalized.Trim('"').Trim("'")
    $normalized = $normalized.Replace("&amp;", "&")

    if ($normalized -match '^https?://')
    {
        $normalized = $normalized.TrimEnd('/')
    }
    elseif ($normalized -match '^//')
    {
        $normalized = "https:$normalized"
    }
    elseif ($normalized.StartsWith("/"))
    {
        $normalized = "https://pcvrcentral.com$normalized"
    }
    else
    {
        $normalized = "https://pcvrcentral.com/$normalized"
    }

    $normalized = $normalized.Split('?')[0]
    $normalized = $normalized.Split('#')[0]
    $normalized = $normalized.TrimEnd('/')

    if ($normalized -notmatch '^https?://pcvrcentral\.com/mods/')
    {
        return $null
    }

    if ($normalized -match '/mods/(all-games|frameworks|guides|mods)(/|$)')
    {
        return $null
    }

    $pathPart = $normalized -replace '^https?://pcvrcentral\.com', ''
    $pathPart = $pathPart.TrimStart('/')

    if ($pathPart -notmatch '^mods/[^/]+')
    {
        return $null
    }

    $slug = ($pathPart -replace '^mods/', '')
    $slug = $slug.Trim('/')

    if ($slug -match '^[0-9]+$')
    {
        return $null
    }

    if ($slug -notmatch '[A-Za-z]')
    {
        return $null
    }

    return $normalized
}

function Is-ValidModPageUrl
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $normalized = Normalize-ModUrl -Url $Url
    if (-not $normalized)
    {
        return $false
    }

    return $true
}

function Get-GameModPageLinks
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$GameUrl
    )

    $client = New-Object System.Net.WebClient
    $client.Encoding = [System.Text.Encoding]::UTF8
    $client.Headers["User-Agent"] = "Mozilla/5.0"

    $html = $client.DownloadString($GameUrl)

    $urls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $patterns = @(
        '(?i)href\s*=\s*["''](?<url>/mods/[^"'']+|https?://pcvrcentral\.com/mods/[^"'']+)["'']',
        '(?i)(?:data-href|href|content|url)\s*[:=]\s*["''](?<url>/mods/[^"'']+|https?://pcvrcentral\.com/mods/[^"'']+)["'']',
        '(?i)(?<url>/mods/[A-Za-z0-9\-_]+)',
        '(?i)(?<url>https?://pcvrcentral\.com/mods/[A-Za-z0-9\-_]+)'
    )

    foreach ($pattern in $patterns)
    {
        $matches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($match in $matches)
        {
            $candidate = $null

            if ($match.Groups["url"].Success)
            {
                $candidate = $match.Groups["url"].Value
            }
            else
            {
                $candidate = $match.Value
            }

            if (Is-ValidModPageUrl -Url $candidate)
            {
                $normalized = Normalize-ModUrl -Url $candidate
                $null = $urls.Add($normalized)
            }
        }
    }

    if ($urls.Count -eq 0)
    {
        $plainMatches = [regex]::Matches(
            $html,
            '(?i)(/mods/[A-Za-z0-9\-_]+|https?://pcvrcentral\.com/mods/[A-Za-z0-9\-_]+)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        foreach ($match in $plainMatches)
        {
            if (Is-ValidModPageUrl -Url $match.Value)
            {
                $normalized = Normalize-ModUrl -Url $match.Value
                $null = $urls.Add($normalized)
            }
        }
    }

    return @($urls | Sort-Object)
}

function Get-FullDetailsSection
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $pos = $Html.IndexOf("Full details", [System.StringComparison]::OrdinalIgnoreCase)
    if ($pos -lt 0)
    {
        return $Html
    }

    $section = $Html.Substring($pos)

    $sourcePos = $section.IndexOf("Source", [System.StringComparison]::OrdinalIgnoreCase)
    if ($sourcePos -gt 0)
    {
        $section = $section.Substring(0, $sourcePos)
    }

    return $section
}

function Clean-HTMLText
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text))
    {
        return ""
    }

    $clean = [regex]::Replace($Text, '(?is)<br\s*/?>', ' ')
    $clean = [regex]::Replace($clean, '(?is)<[^>]+>', ' ')
    $clean = [System.Net.WebUtility]::HtmlDecode($clean)
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()

    return $clean
}

function Get-FieldValueByLabel
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Html))
    {
        return ""
    }

    $labelText = $Label.Trim()
    if ([string]::IsNullOrWhiteSpace($labelText))
    {
        return ""
    }

    $patterns = @(
        "(?is)<(?:div|span|li|p|td|th)[^>]*>\s*(?:<[^>]+>\s*)*{0}\s*(?:</[^>]+>\s*)*</(?:div|span|li|p|td|th)>\s*(?:<(?:div|span|li|p|td|th|a)[^>]*>\s*)*(?<value>.*?)(?=\s*</(?:div|span|li|p|td|th|a)>)",
        "(?is){0}\s*(?:</(?:div|span|li|p|td|th)>\s*){0,2}<(?:div|span|li|p|td|th|a)[^>]*>\s*(?<value>.*?)(?=\s*</(?:div|span|li|p|td|th|a)>)",
        "(?is)(?:<[^>]+>\s*)*{0}(?:\s*</[^>]+>)*\s*(?:<[^>]+>\s*)+(?<value>.+?)(?=\s*</(?:div|span|li|p|td|th|a)>)"
    )

    foreach ($pattern in $patterns)
    {
        $escapedLabel = [regex]::Escape($labelText)
        $regexPattern = [string]::Format($pattern, $escapedLabel)

        $match = [regex]::Match(
            $Html,
            $regexPattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if ($match.Success)
        {
            $value = $match.Groups["value"].Value
            $value = [regex]::Replace($value, '(?is)<[^>]+>', ' ')
            $value = [System.Net.WebUtility]::HtmlDecode($value)
            $value = [regex]::Replace($value, '\s+', ' ').Trim()

            if (-not [string]::IsNullOrWhiteSpace($value))
            {
                return $value
            }
        }
    }

    $section = Get-FullDetailsSection -Html $Html
    $rows = [regex]::Matches($section, '(?is)<(?:tr|div|li|p|span)[^>]*>(.*?)</(?:tr|div|li|p|span)>')

    foreach ($row in $rows)
    {
        $text = Clean-HTMLText -Text $row.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($text))
        {
            if ($text -imatch "^(?<label>Framework|Motion controls|Motion control|Platform|Platforms|VR implementation|Price)\s*(?:[:\-]|[\s]{1,})+(?<value>.+)$")
            {
                $labelFound = $Matches["label"].Trim()
                $valueFound = $Matches["value"].Trim()

                if ($labelFound -ieq $Label -and -not [string]::IsNullOrWhiteSpace($valueFound))
                {
                    return $valueFound
                }
            }
        }
    }

    return ""
}

function Get-DetailRowValue
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    return Get-FieldValueByLabel -Html $Html -Label $Label
}

function Normalize-PCVRFrameworkValue
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$ModPageUrl
    )

    $raw = if ($Value) { [string]$Value.Trim() } else { "" }

    if (-not [string]::IsNullOrWhiteSpace($raw))
    {
        $clean = [regex]::Replace($raw, '\s+', ' ').Trim()
        $lower = $clean.ToLowerInvariant()

        if ($lower -eq "unknown")
        {
            return "Unknown"
        }

        $compact = ($lower -replace '[^a-z0-9]', '')

        if ($compact -match 'real')
        {
            return "R.E.A.L. VR"
        }

        $normalizedLower = $lower -replace '\.', ''
        $normalizedLower = $normalizedLower -replace '[^a-z0-9\s-]', ' '
        $normalizedLower = [regex]::Replace($normalizedLower, '\s+', ' ').Trim()

        switch -Regex ($normalizedLower)
        {
            '^(dedicated\s+vr\s+mod)$' { return "Dedicated VR mod" }
            '^(vorpx)$' { return "VorpX" }
            '^(uevr\s+profile)$' { return "UEVR profile" }
            '^(pcvr)$' { return "PCVR" }
            '^(uuvr)$' { return "UUVR" }
            '^(depth3d)$' { return "Depth3D" }
            '^(unknown)$' { return "Unknown" }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ModPageUrl))
    {
        $lowerUrl = $ModPageUrl.ToLowerInvariant()

        $special = @{
            "questzdoom" = "QuestZDoom"
            "gz3doom" = "gz3doom"
            "razexr" = "RazeXR"
            "jk-xr" = "JK-XR"
            "beef-raider-xr" = "Beef Raider XR"
        }

        foreach ($entry in $special.GetEnumerator())
        {
            if ($lowerUrl.Contains($entry.Key))
            {
                return $entry.Value
            }
        }
    }

    return ""
}

function Normalize-PCVRMotionControlValue
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $allowed = @{
        "gamepad only" = "Gamepad only"
        "full motion controls" = "Full motion controls"
        "partial motion controls" = "Partial motion controls"
        "unknown" = "Unknown"
    }

    $raw = if ($Value) { [string]$Value.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($raw))
    {
        return ""
    }

    $normalized = [regex]::Replace($raw, '\s+', ' ').Trim()
    $key = $normalized.ToLowerInvariant()

    if ($allowed.ContainsKey($key))
    {
        return $allowed[$key]
    }

    return ""
}

function Normalize-PCVRPlatformValues
{
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $raw = if ($Value) { [string]$Value.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($raw))
    {
        return @()
    }

    $normalized = [regex]::Replace($raw, '\s+', ' ').Trim()
    $splitPattern = '(?i)\s*(?:,|/|;|\band\b|\+)\s*'
    $parts = [regex]::Split($normalized, $splitPattern)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($part in $parts)
    {
        $candidate = [regex]::Replace($part, '[^A-Za-z0-9\s]', ' ').Trim()
        $candidate = [regex]::Replace($candidate, '\s+', ' ').Trim()

        if ([string]::IsNullOrWhiteSpace($candidate))
        {
            continue
        }

        $lower = $candidate.ToLowerInvariant()

        if ($lower -match 'meta quest|oculus quest|quest\s*2|quest\s*3|quest')
        {
            $platform = "Quest"
        }
        elseif ($lower -match 'pico|pico\s*4|pico\s*neo')
        {
            $platform = "Pico"
        }
        elseif ($lower -match 'psvr\s*2|psvr2|playstation\s*vr\s*2')
        {
            $platform = "PSVR2"
        }
        elseif ($lower -match 'pcvr|pc-vr')
        {
            $platform = "PCVR"
        }
        else
        {
            $platform = ""
        }

        if ($platform -ieq "PCVR")
        {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($platform) -and $seen.Add($platform))
        {
            $result.Add($platform)
        }
    }

    return @($result)
}

function Get-ModPageDetails
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModPageUrl
    )

    try
    {
        $client = New-Object System.Net.WebClient
        $client.Encoding = [System.Text.Encoding]::UTF8
        $client.Headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        $client.Headers["Accept"] = "text/html,application/xhtml+xml,*/*"

        $html = $client.DownloadString($ModPageUrl)

        $framework = Get-DetailRowValue -Html $html -Label "Framework"
        $motion = Get-DetailRowValue -Html $html -Label "Motion controls"

        if ([string]::IsNullOrWhiteSpace($motion))
        {
            $motion = Get-DetailRowValue -Html $html -Label "Motion control"
        }

        $platform = ""
        foreach ($platformLabel in @("Platform", "Platforms"))
        {
            $platform = Get-DetailRowValue -Html $html -Label $platformLabel
            if (-not [string]::IsNullOrWhiteSpace($platform))
            {
                break
            }
        }

        $framework = Normalize-PCVRFrameworkValue -Value $framework -ModPageUrl $ModPageUrl
        $motion = Normalize-PCVRMotionControlValue -Value $motion
        $platforms = Normalize-PCVRPlatformValues -Value $platform

        return [PSCustomObject]@{
            Framework = [string]$framework
            MotionControl = [string]$motion
            Platforms = @($platforms)
        }
    }
    catch
    {
        return [PSCustomObject]@{
            Framework = ""
            MotionControl = ""
            Platforms = @()
        }
    }
}

function Get-ModRowKey
{
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Item
    )

    $normalizedName = ""
    if ($Item.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$Item.NormalizedName))
    {
        $normalizedName = [string]$Item.NormalizedName
    }
    elseif ($Item.PSObject.Properties.Name -contains "GameName" -and -not [string]::IsNullOrWhiteSpace([string]$Item.GameName))
    {
        $normalizedName = Normalize-GameName -Name ([string]$Item.GameName)
    }

    $modPageUrl = ""
    if ($Item.PSObject.Properties.Name -contains "ModPageUrl" -and -not [string]::IsNullOrWhiteSpace([string]$Item.ModPageUrl))
    {
        $modPageUrl = [string]$Item.ModPageUrl
    }

    if ([string]::IsNullOrWhiteSpace($normalizedName) -and [string]::IsNullOrWhiteSpace($modPageUrl))
    {
        return ""
    }

    return "$normalizedName|$modPageUrl"
}

function Save-PCVRCentralModlist
{
    $catalog = Import-PCVRCentralGamelist
    $outputPath = Get-PCVRCentralModlistPath
    $oldPath = Get-PCVRCentralModlistOldPath
    $gamelistUpdatePath = Get-PCVRCentralGamelistUpdatePath

    if (Test-Path $outputPath)
    {
        if (Test-Path $oldPath)
        {
            Remove-Item -Path $oldPath -Force -ErrorAction SilentlyContinue
        }

        Move-Item -Path $outputPath -Destination $oldPath -Force -ErrorAction Stop
    }

    $changedNormalizedNames = Get-ChangedGameNormalizedNames -UpdateCsvPath $gamelistUpdatePath

    $gamesToProcess = @()

    if ($changedNormalizedNames.Count -gt 0)
    {
        $gamesToProcess = @($catalog | Where-Object { $changedNormalizedNames -contains $_.NormalizedName })
    }
    elseif (-not (Test-Path $oldPath))
    {
        $gamesToProcess = @($catalog)
    }
    else
    {
        $gamesToProcess = @()
    }

    $newRows = @()

    foreach ($game in $gamesToProcess)
    {
        $modUrls = @()
        try
        {
            $modUrls = Get-GameModPageLinks -GameUrl $game.Url
        }
        catch
        {
            $modUrls = @()
        }

        foreach ($modUrl in $modUrls)
        {
            try
            {
                $details = Get-ModPageDetails -ModPageUrl $modUrl

                $platformValues = @($details.Platforms)
                while ($platformValues.Count -lt 10)
                {
                    $platformValues += ""
                }

                $newRows += [PSCustomObject]@{
                    NormalizedName = [string]$game.NormalizedName
                    GameName = [string]$game.Name
                    MainGameUrl = [string]$game.Url
                    ModPageUrl = [string]$modUrl
                    Framework = Normalize-PCVRFrameworkValue -Value ([string]$details.Framework) -ModPageUrl $modUrl
                    MotionControl = Normalize-PCVRMotionControlValue -Value ([string]$details.MotionControl)
                    Platform1 = $platformValues[0]
                    Platform2 = $platformValues[1]
                    Platform3 = $platformValues[2]
                    Platform4 = $platformValues[3]
                    Platform5 = $platformValues[4]
                    Platform6 = $platformValues[5]
                    Platform7 = $platformValues[6]
                    Platform8 = $platformValues[7]
                    Platform9 = $platformValues[8]
                    Platform10 = $platformValues[9]
                }
            }
            catch
            {
                continue
            }
        }
    }

    $finalRows = @()

    if (Test-Path $oldPath)
    {
        $existingRows = Import-Csv -Path $oldPath -Delimiter ';' -Encoding UTF8

        if ($changedNormalizedNames.Count -gt 0)
        {
            $filteredOldRows = @()
            foreach ($row in $existingRows)
            {
                $normalized = ""
                if ($row.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$row.NormalizedName))
                {
                    $normalized = [string]$row.NormalizedName
                }
                elseif ($row.PSObject.Properties.Name -contains "GameName" -and -not [string]::IsNullOrWhiteSpace([string]$row.GameName))
                {
                    $normalized = Normalize-GameName -Name ([string]$row.GameName)
                }

                if (-not [string]::IsNullOrWhiteSpace($normalized) -and $changedNormalizedNames -notcontains $normalized)
                {
                    $filteredOldRows += $row
                }
            }

            $finalRows = @($filteredOldRows)
        }
        else
        {
            $finalRows = @($existingRows)
        }
    }

    foreach ($row in $newRows)
    {
        $finalRows += $row
    }

    $dedupedRows = @()
    $seenKeys = @{}

    foreach ($row in $finalRows)
    {
        $key = Get-ModRowKey -Item $row

        if ([string]::IsNullOrWhiteSpace($key))
        {
            continue
        }

        if (-not $seenKeys.ContainsKey($key))
        {
            $seenKeys[$key] = $true
            $dedupedRows += $row
        }
    }

    if ($dedupedRows.Count -gt 0)
    {
        $dedupedRows |
            Select-Object NormalizedName, GameName, MainGameUrl, ModPageUrl, Framework, MotionControl,
                Platform1, Platform2, Platform3, Platform4, Platform5, Platform6, Platform7, Platform8, Platform9, Platform10 |
            Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else
    {
        [PSCustomObject]@{
            NormalizedName = ""
            GameName = ""
            MainGameUrl = ""
            ModPageUrl = ""
            Framework = ""
            MotionControl = ""
            Platform1 = ""
            Platform2 = ""
            Platform3 = ""
            Platform4 = ""
            Platform5 = ""
            Platform6 = ""
            Platform7 = ""
            Platform8 = ""
            Platform9 = ""
            Platform10 = ""
        } |
            Select-Object NormalizedName, GameName, MainGameUrl, ModPageUrl, Framework, MotionControl,
                Platform1, Platform2, Platform3, Platform4, Platform5, Platform6, Platform7, Platform8, Platform9, Platform10 |
            Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    return $outputPath
}

function Save-PCVRCentralModlistUpdate
{
    $currentPath = Get-PCVRCentralModlistPath
    $oldPath = Get-PCVRCentralModlistOldPath
    $updatePath = Get-PCVRCentralModlistUpdatePath

    if (-not (Test-Path $currentPath))
    {
        $currentPath = Save-PCVRCentralModlist
    }

    $newItems = @()
    if (Test-Path $currentPath)
    {
        $newItems = Import-Csv -Path $currentPath -Delimiter ';' -Encoding UTF8
    }

    $oldItems = @()
    if (Test-Path $oldPath)
    {
        $oldItems = Import-Csv -Path $oldPath -Delimiter ';' -Encoding UTF8
    }

    $oldByKey = @{}
    foreach ($item in $oldItems)
    {
        $key = Get-ModRowKey -Item $item
        if ([string]::IsNullOrWhiteSpace($key))
        {
            continue
        }

        $oldByKey[$key] = $item
    }

    $newByKey = @{}
    foreach ($item in $newItems)
    {
        $key = Get-ModRowKey -Item $item
        if ([string]::IsNullOrWhiteSpace($key))
        {
            continue
        }

        $newByKey[$key] = $item
    }

    $allKeys = @()
    foreach ($key in $oldByKey.Keys)
    {
        $allKeys += $key
    }
    foreach ($key in $newByKey.Keys)
    {
        if ($allKeys -notcontains $key)
        {
            $allKeys += $key
        }
    }

    $changes = @()

    foreach ($key in ($allKeys | Sort-Object -Unique))
    {
        $oldItem = $null
        if ($oldByKey.ContainsKey($key))
        {
            $oldItem = $oldByKey[$key]
        }

        $newItem = $null
        if ($newByKey.ContainsKey($key))
        {
            $newItem = $newByKey[$key]
        }

        if (-not $oldItem -and $newItem)
        {
            $oldPlatformValues = @("", "", "", "", "", "", "", "", "", "")
            $newPlatformValues = @()

            for ($i = 1; $i -le 10; $i++)
            {
                $prop = "Platform$i"
                if ($newItem.PSObject.Properties.Name -contains $prop)
                {
                    $newPlatformValues += [string]$newItem.$prop
                }
                else
                {
                    $newPlatformValues += ""
                }
            }

            while ($newPlatformValues.Count -lt 10)
            {
                $newPlatformValues += ""
            }

            $changes += [PSCustomObject]@{
                NormalizedName = if ($newItem.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$newItem.NormalizedName)) { [string]$newItem.NormalizedName } else { Normalize-GameName -Name ([string]$newItem.GameName) }
                GameName = [string]$newItem.GameName
                MainGameUrl = [string]$newItem.MainGameUrl
                OldModPageUrl = ""
                NewModPageUrl = [string]$newItem.ModPageUrl
                OldFramework = ""
                NewFramework = [string]$newItem.Framework
                OldMotionControl = ""
                NewMotionControl = [string]$newItem.MotionControl
                OldPlatform1 = $oldPlatformValues[0]; NewPlatform1 = $newPlatformValues[0]
                OldPlatform2 = $oldPlatformValues[1]; NewPlatform2 = $newPlatformValues[1]
                OldPlatform3 = $oldPlatformValues[2]; NewPlatform3 = $newPlatformValues[2]
                OldPlatform4 = $oldPlatformValues[3]; NewPlatform4 = $newPlatformValues[3]
                OldPlatform5 = $oldPlatformValues[4]; NewPlatform5 = $newPlatformValues[4]
                OldPlatform6 = $oldPlatformValues[5]; NewPlatform6 = $newPlatformValues[5]
                OldPlatform7 = $oldPlatformValues[6]; NewPlatform7 = $newPlatformValues[6]
                OldPlatform8 = $oldPlatformValues[7]; NewPlatform8 = $newPlatformValues[7]
                OldPlatform9 = $oldPlatformValues[8]; NewPlatform9 = $newPlatformValues[8]
                OldPlatform10 = $oldPlatformValues[9]; NewPlatform10 = $newPlatformValues[9]
            }
            continue
        }

        if ($oldItem -and -not $newItem)
        {
            $oldPlatformValues = @()
            for ($i = 1; $i -le 10; $i++)
            {
                $prop = "Platform$i"
                if ($oldItem.PSObject.Properties.Name -contains $prop)
                {
                    $oldPlatformValues += [string]$oldItem.$prop
                }
                else
                {
                    $oldPlatformValues += ""
                }
            }

            while ($oldPlatformValues.Count -lt 10)
            {
                $oldPlatformValues += ""
            }

            $changes += [PSCustomObject]@{
                NormalizedName = if ($oldItem.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$oldItem.NormalizedName)) { [string]$oldItem.NormalizedName } else { Normalize-GameName -Name ([string]$oldItem.GameName) }
                GameName = [string]$oldItem.GameName
                MainGameUrl = [string]$oldItem.MainGameUrl
                OldModPageUrl = [string]$oldItem.ModPageUrl
                NewModPageUrl = ""
                OldFramework = [string]$oldItem.Framework
                NewFramework = ""
                OldMotionControl = [string]$oldItem.MotionControl
                NewMotionControl = ""
                OldPlatform1 = $oldPlatformValues[0]; NewPlatform1 = ""
                OldPlatform2 = $oldPlatformValues[1]; NewPlatform2 = ""
                OldPlatform3 = $oldPlatformValues[2]; NewPlatform3 = ""
                OldPlatform4 = $oldPlatformValues[3]; NewPlatform4 = ""
                OldPlatform5 = $oldPlatformValues[4]; NewPlatform5 = ""
                OldPlatform6 = $oldPlatformValues[5]; NewPlatform6 = ""
                OldPlatform7 = $oldPlatformValues[6]; NewPlatform7 = ""
                OldPlatform8 = $oldPlatformValues[7]; NewPlatform8 = ""
                OldPlatform9 = $oldPlatformValues[8]; NewPlatform9 = ""
                OldPlatform10 = $oldPlatformValues[9]; NewPlatform10 = ""
            }
            continue
        }

        if ($oldItem -and $newItem)
        {
            $oldFramework = [string]$oldItem.Framework
            $newFramework = [string]$newItem.Framework
            $oldMotionControl = [string]$oldItem.MotionControl
            $newMotionControl = [string]$newItem.MotionControl
            $oldModPageUrl = [string]$oldItem.ModPageUrl
            $newModPageUrl = [string]$newItem.ModPageUrl

            $oldPlatformValues = @()
            $newPlatformValues = @()

            for ($i = 1; $i -le 10; $i++)
            {
                $oldProp = "Platform$i"
                $newProp = "Platform$i"

                if ($oldItem.PSObject.Properties.Name -contains $oldProp)
                {
                    $oldPlatformValues += [string]$oldItem.$oldProp
                }
                else
                {
                    $oldPlatformValues += ""
                }

                if ($newItem.PSObject.Properties.Name -contains $newProp)
                {
                    $newPlatformValues += [string]$newItem.$newProp
                }
                else
                {
                    $newPlatformValues += ""
                }
            }

            while ($oldPlatformValues.Count -lt 10)
            {
                $oldPlatformValues += ""
            }

            while ($newPlatformValues.Count -lt 10)
            {
                $newPlatformValues += ""
            }

            $platformChanged = $false
            for ($i = 0; $i -le 9; $i++)
            {
                if ($oldPlatformValues[$i] -ne $newPlatformValues[$i])
                {
                    $platformChanged = $true
                    break
                }
            }

            if ($oldFramework -ne $newFramework -or $oldMotionControl -ne $newMotionControl -or $oldModPageUrl -ne $newModPageUrl -or $platformChanged)
            {
                $changes += [PSCustomObject]@{
                    NormalizedName = if ($newItem.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$newItem.NormalizedName)) { [string]$newItem.NormalizedName } else { Normalize-GameName -Name ([string]$newItem.GameName) }
                    GameName = [string]$newItem.GameName
                    MainGameUrl = [string]$newItem.MainGameUrl
                    OldModPageUrl = $oldModPageUrl
                    NewModPageUrl = $newModPageUrl
                    OldFramework = $oldFramework
                    NewFramework = $newFramework
                    OldMotionControl = $oldMotionControl
                    NewMotionControl = $newMotionControl
                    OldPlatform1 = $oldPlatformValues[0]; NewPlatform1 = $newPlatformValues[0]
                    OldPlatform2 = $oldPlatformValues[1]; NewPlatform2 = $newPlatformValues[1]
                    OldPlatform3 = $oldPlatformValues[2]; NewPlatform3 = $newPlatformValues[2]
                    OldPlatform4 = $oldPlatformValues[3]; NewPlatform4 = $newPlatformValues[3]
                    OldPlatform5 = $oldPlatformValues[4]; NewPlatform5 = $newPlatformValues[4]
                    OldPlatform6 = $oldPlatformValues[5]; NewPlatform6 = $newPlatformValues[5]
                    OldPlatform7 = $oldPlatformValues[6]; NewPlatform7 = $newPlatformValues[6]
                    OldPlatform8 = $oldPlatformValues[7]; NewPlatform8 = $newPlatformValues[7]
                    OldPlatform9 = $oldPlatformValues[8]; NewPlatform9 = $newPlatformValues[8]
                    OldPlatform10 = $oldPlatformValues[9]; NewPlatform10 = $newPlatformValues[9]
                }
            }
        }
    }

    if ($changes.Count -gt 0)
    {
        $changes |
            Select-Object NormalizedName, GameName, MainGameUrl, OldModPageUrl, NewModPageUrl, OldFramework, NewFramework, OldMotionControl, NewMotionControl,
                OldPlatform1, NewPlatform1, OldPlatform2, NewPlatform2, OldPlatform3, NewPlatform3, OldPlatform4, NewPlatform4,
                OldPlatform5, NewPlatform5, OldPlatform6, NewPlatform6, OldPlatform7, NewPlatform7, OldPlatform8, NewPlatform8,
                OldPlatform9, NewPlatform9, OldPlatform10, NewPlatform10 |
            Export-Csv -Path $updatePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else
    {
        [PSCustomObject]@{
            NormalizedName = ""
            GameName = ""
            MainGameUrl = ""
            OldModPageUrl = ""
            NewModPageUrl = ""
            OldFramework = ""
            NewFramework = ""
            OldMotionControl = ""
            NewMotionControl = ""
            OldPlatform1 = ""; NewPlatform1 = ""
            OldPlatform2 = ""; NewPlatform2 = ""
            OldPlatform3 = ""; NewPlatform3 = ""
            OldPlatform4 = ""; NewPlatform4 = ""
            OldPlatform5 = ""; NewPlatform5 = ""
            OldPlatform6 = ""; NewPlatform6 = ""
            OldPlatform7 = ""; NewPlatform7 = ""
            OldPlatform8 = ""; NewPlatform8 = ""
            OldPlatform9 = ""; NewPlatform9 = ""
            OldPlatform10 = ""; NewPlatform10 = ""
        } |
            Select-Object NormalizedName, GameName, MainGameUrl, OldModPageUrl, NewModPageUrl, OldFramework, NewFramework, OldMotionControl, NewMotionControl,
                OldPlatform1, NewPlatform1, OldPlatform2, NewPlatform2, OldPlatform3, NewPlatform3, OldPlatform4, NewPlatform4,
                OldPlatform5, NewPlatform5, OldPlatform6, NewPlatform6, OldPlatform7, NewPlatform7, OldPlatform8, NewPlatform8,
                OldPlatform9, NewPlatform9, OldPlatform10, NewPlatform10 |
            Export-Csv -Path $updatePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    return $updatePath
}

function Get-PCVRCentralAggregatedTags
{
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$ModRows
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $tags = New-Object System.Collections.Generic.List[string]

    if (-not $ModRows)
    {
        return @()
    }

    foreach ($row in $ModRows)
    {
        foreach ($fieldName in @("Framework", "MotionControl"))
        {
            if (-not $row.PSObject.Properties.Name -contains $fieldName)
            {
                continue
            }

            $value = [string]$row.$fieldName
            if ([string]::IsNullOrWhiteSpace($value))
            {
                continue
            }

            $normalized = [regex]::Replace($value, '\s+', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($normalized))
            {
                continue
            }

            if ($seen.Add($normalized))
            {
                $tags.Add($normalized)
            }
        }

        for ($i = 1; $i -le 10; $i++)
        {
            $platformProp = "Platform$i"
            if ($row.PSObject.Properties.Name -contains $platformProp)
            {
                $value = [string]$row.$platformProp
                if (-not [string]::IsNullOrWhiteSpace($value))
                {
                    $normalized = [regex]::Replace($value, '\s+', ' ').Trim()
                    if (-not [string]::IsNullOrWhiteSpace($normalized) -and $normalized -ne "PCVR" -and $seen.Add($normalized))
                    {
                        $tags.Add($normalized)
                    }
                }
            }
        }
    }

    return @($tags | Select-Object -First 20)
}

function Save-PCVRCentralTaglist
{
    $gamelistPath = Get-PCVRCentralGamelistPath
    $modlistPath = Get-PCVRCentralModlistPath
    $outputPath = Get-PCVRCentralTaglistPath
    $oldPath = Get-PCVRCentralTaglistOldPath

    if (Test-Path $gamelistPath)
    {
        $games = Import-Csv -Path $gamelistPath -Delimiter ';' -Encoding UTF8
    }
    else
    {
        $games = @(Import-Csv -Path (Save-PCVRCentralGamelist) -Delimiter ';' -Encoding UTF8)
    }

    if (Test-Path $modlistPath)
    {
        $modRows = Import-Csv -Path $modlistPath -Delimiter ';' -Encoding UTF8
    }
    else
    {
        $modRows = @()
    }

    $groupedMods = @{}
    foreach ($modRow in $modRows)
    {
        $key = ""
        if ($modRow.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$modRow.NormalizedName))
        {
            $key = [string]$modRow.NormalizedName
        }
        elseif ($modRow.PSObject.Properties.Name -contains "GameName" -and -not [string]::IsNullOrWhiteSpace([string]$modRow.GameName))
        {
            $key = Normalize-GameName -Name ([string]$modRow.GameName)
        }

        if ([string]::IsNullOrWhiteSpace($key))
        {
            continue
        }

        if (-not $groupedMods.ContainsKey($key))
        {
            $groupedMods[$key] = @()
        }

        $groupedMods[$key] += $modRow
    }

    $resultRows = @()

    foreach ($game in $games)
    {
        $normalizedName = ""
        if ($game.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$game.NormalizedName))
        {
            $normalizedName = [string]$game.NormalizedName
        }
        else
        {
            $normalizedName = Normalize-GameName -Name ([string]$game.Name)
        }

        $gameName = if ($game.PSObject.Properties.Name -contains "Name") { [string]$game.Name } else { "" }
        $gameUrl = if ($game.PSObject.Properties.Name -contains "Url") { [string]$game.Url } else { "" }
        $methodCount = if ($game.PSObject.Properties.Name -contains "MethodCount" -and -not [string]::IsNullOrWhiteSpace([string]$game.MethodCount)) { [int]$game.MethodCount } else { 0 }

        $modEntries = @()
        if (-not [string]::IsNullOrWhiteSpace($normalizedName) -and $groupedMods.ContainsKey($normalizedName))
        {
            $modEntries = @($groupedMods[$normalizedName])
        }

        $aggregatedTags = @(Get-PCVRCentralAggregatedTags -ModRows $modEntries)

        while ($aggregatedTags.Count -lt 20)
        {
            $aggregatedTags += ""
        }

        $pcvrTag = if ($methodCount -gt 0) { "PCVR-Mod" } else { "PCVR-Native" }

        $resultRows += [PSCustomObject]@{
            NormalizedName = $normalizedName
            GameName = $gameName
            PCVRCentralUrl = $gameUrl
            PCVRTag = $pcvrTag
            Tag1 = $aggregatedTags[0]
            Tag2 = $aggregatedTags[1]
            Tag3 = $aggregatedTags[2]
            Tag4 = $aggregatedTags[3]
            Tag5 = $aggregatedTags[4]
            Tag6 = $aggregatedTags[5]
            Tag7 = $aggregatedTags[6]
            Tag8 = $aggregatedTags[7]
            Tag9 = $aggregatedTags[8]
            Tag10 = $aggregatedTags[9]
            Tag11 = $aggregatedTags[10]
            Tag12 = $aggregatedTags[11]
            Tag13 = $aggregatedTags[12]
            Tag14 = $aggregatedTags[13]
            Tag15 = $aggregatedTags[14]
            Tag16 = $aggregatedTags[15]
            Tag17 = $aggregatedTags[16]
            Tag18 = $aggregatedTags[17]
            Tag19 = $aggregatedTags[18]
            Tag20 = $aggregatedTags[19]
        }
    }

    if (Test-Path $outputPath)
    {
        if (Test-Path $oldPath)
        {
            Remove-Item -Path $oldPath -Force -ErrorAction SilentlyContinue
        }

        Move-Item -Path $outputPath -Destination $oldPath -Force -ErrorAction Stop
    }

    if ($resultRows.Count -gt 0)
    {
        $resultRows |
            Select-Object NormalizedName, GameName, PCVRCentralUrl, PCVRTag,
                Tag1, Tag2, Tag3, Tag4, Tag5, Tag6, Tag7, Tag8, Tag9, Tag10,
                Tag11, Tag12, Tag13, Tag14, Tag15, Tag16, Tag17, Tag18, Tag19, Tag20 |
            Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else
    {
        [PSCustomObject]@{
            NormalizedName = ""
            GameName = ""
            PCVRCentralUrl = ""
            PCVRTag = ""
            Tag1 = ""; Tag2 = ""; Tag3 = ""; Tag4 = ""; Tag5 = ""; Tag6 = ""; Tag7 = ""; Tag8 = ""; Tag9 = ""; Tag10 = ""
            Tag11 = ""; Tag12 = ""; Tag13 = ""; Tag14 = ""; Tag15 = ""; Tag16 = ""; Tag17 = ""; Tag18 = ""; Tag19 = ""; Tag20 = ""
        } |
            Select-Object NormalizedName, GameName, PCVRCentralUrl, PCVRTag,
                Tag1, Tag2, Tag3, Tag4, Tag5, Tag6, Tag7, Tag8, Tag9, Tag10,
                Tag11, Tag12, Tag13, Tag14, Tag15, Tag16, Tag17, Tag18, Tag19, Tag20 |
            Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    return $outputPath
}

function Save-PCVRCentralTaglistUpdate
{
    $currentPath = Get-PCVRCentralTaglistPath
    $oldPath = Get-PCVRCentralTaglistOldPath
    $updatePath = Get-PCVRCentralTaglistUpdatePath

    if (-not (Test-Path $currentPath))
    {
        $currentPath = Save-PCVRCentralTaglist
    }

    $newItems = @()
    if (Test-Path $currentPath)
    {
        $newItems = Import-Csv -Path $currentPath -Delimiter ';' -Encoding UTF8
    }

    $oldItems = @()
    if (Test-Path $oldPath)
    {
        $oldItems = Import-Csv -Path $oldPath -Delimiter ';' -Encoding UTF8
    }

    $oldByKey = @{}
    foreach ($item in $oldItems)
    {
        $key = if ($item.NormalizedName) { [string]$item.NormalizedName } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($key))
        {
            $oldByKey[$key] = $item
        }
    }

    $newByKey = @{}
    foreach ($item in $newItems)
    {
        $key = if ($item.NormalizedName) { [string]$item.NormalizedName } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($key))
        {
            $newByKey[$key] = $item
        }
    }

    $allKeys = @()
    foreach ($key in $oldByKey.Keys)
    {
        $allKeys += $key
    }
    foreach ($key in $newByKey.Keys)
    {
        if ($allKeys -notcontains $key)
        {
            $allKeys += $key
        }
    }

    $changes = @()

    foreach ($key in ($allKeys | Sort-Object -Unique))
    {
        $oldItem = $null
        if ($oldByKey.ContainsKey($key))
        {
            $oldItem = $oldByKey[$key]
        }

        $newItem = $null
        if ($newByKey.ContainsKey($key))
        {
            $newItem = $newByKey[$key]
        }

        $oldPCVRTag = if ($oldItem) { [string]$oldItem.PCVRTag } else { "" }
        $newPCVRTag = if ($newItem) { [string]$newItem.PCVRTag } else { "" }

        $oldTagValues = @()
        $newTagValues = @()

        for ($i = 1; $i -le 20; $i++)
        {
            $prop = "Tag$i"
            $oldTagValues += if ($oldItem -and ($oldItem.PSObject.Properties.Name -contains $prop)) { [string]$oldItem.$prop } else { "" }
            $newTagValues += if ($newItem -and ($newItem.PSObject.Properties.Name -contains $prop)) { [string]$newItem.$prop } else { "" }
        }

        $changed = $false
        if ($oldPCVRTag -ne $newPCVRTag) { $changed = $true }
        for ($i = 0; $i -le 19; $i++)
        {
            if ($oldTagValues[$i] -ne $newTagValues[$i])
            {
                $changed = $true
                break
            }
        }

        if (-not $changed)
        {
            continue
        }

        $row = [PSCustomObject]@{
            NormalizedName = if ($newItem) { [string]$newItem.NormalizedName } else { [string]$oldItem.NormalizedName }
            GameName = if ($newItem) { [string]$newItem.GameName } else { [string]$oldItem.GameName }
            OldPCVRTag = $oldPCVRTag
            NewPCVRTag = $newPCVRTag
            OldTag1 = $oldTagValues[0]; NewTag1 = $newTagValues[0]
            OldTag2 = $oldTagValues[1]; NewTag2 = $newTagValues[1]
            OldTag3 = $oldTagValues[2]; NewTag3 = $newTagValues[2]
            OldTag4 = $oldTagValues[3]; NewTag4 = $newTagValues[3]
            OldTag5 = $oldTagValues[4]; NewTag5 = $newTagValues[4]
            OldTag6 = $oldTagValues[5]; NewTag6 = $newTagValues[5]
            OldTag7 = $oldTagValues[6]; NewTag7 = $newTagValues[6]
            OldTag8 = $oldTagValues[7]; NewTag8 = $newTagValues[7]
            OldTag9 = $oldTagValues[8]; NewTag9 = $newTagValues[8]
            OldTag10 = $oldTagValues[9]; NewTag10 = $newTagValues[9]
            OldTag11 = $oldTagValues[10]; NewTag11 = $newTagValues[10]
            OldTag12 = $oldTagValues[11]; NewTag12 = $newTagValues[11]
            OldTag13 = $oldTagValues[12]; NewTag13 = $newTagValues[12]
            OldTag14 = $oldTagValues[13]; NewTag14 = $newTagValues[13]
            OldTag15 = $oldTagValues[14]; NewTag15 = $newTagValues[14]
            OldTag16 = $oldTagValues[15]; NewTag16 = $newTagValues[15]
            OldTag17 = $oldTagValues[16]; NewTag17 = $newTagValues[16]
            OldTag18 = $oldTagValues[17]; NewTag18 = $newTagValues[17]
            OldTag19 = $oldTagValues[18]; NewTag19 = $newTagValues[18]
            OldTag20 = $oldTagValues[19]; NewTag20 = $newTagValues[19]
        }

        $changes += $row
    }

    if ($changes.Count -gt 0)
    {
        $changes |
            Select-Object NormalizedName, GameName, OldPCVRTag, NewPCVRTag,
                OldTag1, NewTag1, OldTag2, NewTag2, OldTag3, NewTag3, OldTag4, NewTag4,
                OldTag5, NewTag5, OldTag6, NewTag6, OldTag7, NewTag7, OldTag8, NewTag8,
                OldTag9, NewTag9, OldTag10, NewTag10,
                OldTag11, NewTag11, OldTag12, NewTag12, OldTag13, NewTag13, OldTag14, NewTag14,
                OldTag15, NewTag15, OldTag16, NewTag16, OldTag17, NewTag17, OldTag18, NewTag18,
                OldTag19, NewTag19, OldTag20, NewTag20 |
            Export-Csv -Path $updatePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else
    {
        [PSCustomObject]@{
            NormalizedName = ""
            GameName = ""
            OldPCVRTag = ""
            NewPCVRTag = ""
            OldTag1 = ""; NewTag1 = ""; OldTag2 = ""; NewTag2 = ""; OldTag3 = ""; NewTag3 = ""; OldTag4 = ""; NewTag4 = ""; OldTag5 = ""; NewTag5 = ""; OldTag6 = ""; NewTag6 = ""; OldTag7 = ""; NewTag7 = ""; OldTag8 = ""; NewTag8 = ""; OldTag9 = ""; NewTag9 = ""; OldTag10 = ""; NewTag10 = ""
            OldTag11 = ""; NewTag11 = ""; OldTag12 = ""; NewTag12 = ""; OldTag13 = ""; NewTag13 = ""; OldTag14 = ""; NewTag14 = ""; OldTag15 = ""; NewTag15 = ""; OldTag16 = ""; NewTag16 = ""; OldTag17 = ""; NewTag17 = ""; OldTag18 = ""; NewTag18 = ""; OldTag19 = ""; NewTag19 = ""; OldTag20 = ""; NewTag20 = ""
        } |
            Select-Object NormalizedName, GameName, OldPCVRTag, NewPCVRTag,
                OldTag1, NewTag1, OldTag2, NewTag2, OldTag3, NewTag3, OldTag4, NewTag4,
                OldTag5, NewTag5, OldTag6, NewTag6, OldTag7, NewTag7, OldTag8, NewTag8,
                OldTag9, NewTag9, OldTag10, NewTag10,
                OldTag11, NewTag11, OldTag12, NewTag12, OldTag13, NewTag13, OldTag14, NewTag14,
                OldTag15, NewTag15, OldTag16, NewTag16, OldTag17, NewTag17, OldTag18, NewTag18,
                OldTag19, NewTag19, OldTag20, NewTag20 |
            Export-Csv -Path $updatePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    return $updatePath
}

function Get-PCVRCentralDesiredTagNamesFromRow
{
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Row
    )

    $result = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $generic = ""
    if ($Row.PSObject.Properties.Name -contains "PCVRTag")
    {
        $generic = [string]$Row.PCVRTag
    }

    if (-not [string]::IsNullOrWhiteSpace($generic))
    {
        $generic = [regex]::Replace($generic, '\s+', ' ').Trim()
        if (-not [string]::IsNullOrWhiteSpace($generic) -and $generic -ne "PCVR")
        {
            $null = $result.Add($generic)
        }
    }

    for ($i = 1; $i -le 20; $i++)
    {
        $prop = "Tag$i"
        if ($Row.PSObject.Properties.Name -contains $prop)
        {
            $value = [string]$Row.$prop
            if (-not [string]::IsNullOrWhiteSpace($value))
            {
                $value = [regex]::Replace($value, '\s+', ' ').Trim()
                if (-not [string]::IsNullOrWhiteSpace($value) -and $value -ne "PCVR")
                {
                    $null = $result.Add($value)
                }
            }
        }
    }

    return @($result | Sort-Object)
}

function Get-PCVRCentralTaglistUpdateNormalizedNames
{
    $path = Get-PCVRCentralTaglistUpdatePath

    if (-not (Test-Path $path))
    {
        return @()
    }

    $items = Import-Csv -Path $path -Delimiter ';' -Encoding UTF8
    $result = @()

    foreach ($item in $items)
    {
        $normalized = ""
        if ($item.PSObject.Properties.Name -contains "NormalizedName")
        {
            $normalized = [string]$item.NormalizedName
        }

        if (-not [string]::IsNullOrWhiteSpace($normalized))
        {
            $result += $normalized
        }
    }

    return @($result | Select-Object -Unique)
}

function Apply-PCVRCentralFinalTagsToPlaynite
{
    $tagListPath = Get-PCVRCentralTaglistPath
    $tagUpdatePath = Get-PCVRCentralTaglistUpdatePath

    if (-not (Test-Path $tagListPath))
    {
        return @()
    }

    $allRows = Import-Csv -Path $tagListPath -Delimiter ';' -Encoding UTF8
    if (-not $allRows)
    {
        return @()
    }

    $tagListByNormalized = @{}
    foreach ($row in $allRows)
    {
        $normalized = ""
        if ($row.PSObject.Properties.Name -contains "NormalizedName")
        {
            $normalized = [string]$row.NormalizedName
        }

        if (-not [string]::IsNullOrWhiteSpace($normalized))
        {
            $tagListByNormalized[$normalized] = $row
        }
    }

    $changedNormalizedNames = @()
    if (Test-Path $tagUpdatePath)
    {
        $changedNormalizedNames = Get-PCVRCentralTaglistUpdateNormalizedNames
    }

    if ($changedNormalizedNames.Count -eq 0)
    {
        return @()
    }

    $managedTagNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($row in $allRows)
    {
        foreach ($tag in (Get-PCVRCentralDesiredTagNamesFromRow -Row $row))
        {
            $null = $managedTagNames.Add($tag)
        }
    }

    $null = $managedTagNames.Add("PCVR-Mod")
    $null = $managedTagNames.Add("PCVR-Native")

    $updatedNormalized = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($game in $PlayniteApi.Database.Games)
    {
        $normalized = Normalize-GameName -Name $game.Name
        if ($changedNormalizedNames -notcontains $normalized)
        {
            continue
        }

        $tagRow = $null
        if ($tagListByNormalized.ContainsKey($normalized))
        {
            $tagRow = $tagListByNormalized[$normalized]
        }

        if (-not $tagRow)
        {
            continue
        }

        $desiredTagNames = @(Get-PCVRCentralDesiredTagNamesFromRow -Row $tagRow)

        foreach ($tagName in $desiredTagNames)
        {
            if (-not [string]::IsNullOrWhiteSpace($tagName))
            {
                $null = Ensure-TagExists -TagName $tagName
            }
        }

        if (-not $game.TagIds)
        {
            $game.TagIds = New-Object System.Collections.Generic.List[System.Guid]
        }

        $desiredIds = [System.Collections.Generic.HashSet[System.Guid]]::new()

        foreach ($tagName in $desiredTagNames)
        {
            $tag = $PlayniteApi.Database.Tags | Where-Object { $_.Name -eq $tagName } | Select-Object -First 1
            if ($tag)
            {
                $null = $desiredIds.Add($tag.Id)
            }
        }

        $changed = $false

        foreach ($tag in $PlayniteApi.Database.Tags)
        {
            if ($managedTagNames.Contains($tag.Name))
            {
                if ($desiredIds.Contains($tag.Id))
                {
                    if (-not $game.TagIds.Contains($tag.Id))
                    {
                        $game.TagIds.Add($tag.Id)
                        $changed = $true
                    }
                }
                else
                {
                    if ($game.TagIds.Contains($tag.Id))
                    {
                        $game.TagIds.Remove($tag.Id)
                        $changed = $true
                    }
                }
            }
        }

        if ($changed)
        {
            $PlayniteApi.Database.Games.Update($game)
            $null = $updatedNormalized.Add($normalized)
        }
    }

    return @($updatedNormalized | Sort-Object)
}

function Start-PCVRCentralSync
{
    param($args)

    try
    {
        $modTag = Ensure-TagExists -TagName "PCVR-Mod"
        $nativeTag = Ensure-TagExists -TagName "PCVR-Native"

        $gamelistPath = Save-PCVRCentralGamelist
        $catalog = Import-PCVRCentralGamelist -CsvPath $gamelistPath

        $gamelistUpdatePath = Save-PCVRCentralGamelistUpdate
        $modListPath = Save-PCVRCentralModlist
        $modListUpdatePath = Save-PCVRCentralModlistUpdate

        $taglistPath = Save-PCVRCentralTaglist
        $taglistUpdatePath = Save-PCVRCentralTaglistUpdate

        $libraryMatchCount = 0
        $updatedNormalized = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($game in $PlayniteApi.Database.Games)
        {
            $normalized = Normalize-GameName -Name $game.Name
            $match = $catalog | Where-Object { $_.NormalizedName -eq $normalized } | Select-Object -First 1

            if (-not $match)
            {
                continue
            }

            $libraryMatchCount++

            $changed = $false

            if (-not $game.TagIds)
            {
                $game.TagIds = New-Object System.Collections.Generic.List[System.Guid]
            }

            if ($match.MethodCount -eq 0)
            {
                if (-not $game.TagIds.Contains($nativeTag.Id))
                {
                    $game.TagIds.Add($nativeTag.Id)
                    $changed = $true
                }

                if ($game.TagIds.Contains($modTag.Id))
                {
                    $game.TagIds.Remove($modTag.Id)
                    $changed = $true
                }
            }
            else
            {
                if (-not $game.TagIds.Contains($modTag.Id))
                {
                    $game.TagIds.Add($modTag.Id)
                    $changed = $true
                }

                if ($game.TagIds.Contains($nativeTag.Id))
                {
                    $game.TagIds.Remove($nativeTag.Id)
                    $changed = $true
                }
            }

            $hasLink = $false
            if ($game.Links)
            {
                foreach ($link in $game.Links)
                {
                    if ($link.Name -eq "PCVR Central")
                    {
                        $hasLink = $true
                        break
                    }
                }
            }

            if (-not $hasLink)
            {
                if (-not $game.Links)
                {
                    $game.Links = New-Object "System.Collections.ObjectModel.ObservableCollection[Playnite.SDK.Models.Link]"
                }

                $game.Links.Add((New-Object Playnite.SDK.Models.Link("PCVR Central", $match.Url)))
                $changed = $true
            }

            if ($changed)
            {
                $PlayniteApi.Database.Games.Update($game)
                $null = $updatedNormalized.Add($normalized)
            }
        }

        $finalTagUpdates = Apply-PCVRCentralFinalTagsToPlaynite
        foreach ($normalized in $finalTagUpdates)
        {
            $null = $updatedNormalized.Add($normalized)
        }

        $message = "$($catalog.Count) Games on PCVR Central found`n$libraryMatchCount Games with matching entries in your library`n$($updatedNormalized.Count) Games with new information updated"

        $PlayniteApi.Dialogs.ShowMessage($message, "PCVR Central Matcher")
    }
    catch
    {
        $PlayniteApi.Dialogs.ShowErrorMessage($_.Exception.ToString(), "PCVR Central Matcher")
    }
}

function GetMainMenuItems
{
    param($args)

    $menuItem = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $menuItem.Description = "PCVR Central Matcher: Sync"
    $menuItem.FunctionName = "Start-PCVRCentralSync"

    return @($menuItem)
}

Export-ModuleMember -Function Ensure-TagExists, Normalize-GameName, Get-GameCatalog, Get-PCVRCentralDataDirectory, Get-PCVRCentralGamelistPath, Get-PCVRCentralGamelistOldPath, Get-PCVRCentralGamelistUpdatePath, Get-PCVRCentralModlistPath, Get-PCVRCentralModlistOldPath, Get-PCVRCentralModlistUpdatePath, Get-PCVRCentralTaglistPath, Get-PCVRCentralTaglistOldPath, Get-PCVRCentralTaglistUpdatePath, Save-PCVRCentralGamelist, Save-PCVRCentralGamelistUpdate, Import-PCVRCentralGamelist, Normalize-ModUrl, Is-ValidModPageUrl, Get-GameModPageLinks, Get-FullDetailsSection, Clean-HTMLText, Get-FieldValueByLabel, Get-DetailRowValue, Normalize-PCVRFrameworkValue, Normalize-PCVRMotionControlValue, Normalize-PCVRPlatformValues, Get-ModPageDetails, Save-PCVRCentralModlist, Save-PCVRCentralModlistUpdate, Get-PCVRCentralAggregatedTags, Save-PCVRCentralTaglist, Save-PCVRCentralTaglistUpdate, Get-PCVRCentralDesiredTagNamesFromRow, Get-PCVRCentralTaglistUpdateNormalizedNames, Apply-PCVRCentralFinalTagsToPlaynite, GetMainMenuItems, Start-PCVRCentralSync
