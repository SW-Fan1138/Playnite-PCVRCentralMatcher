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
    $candidatePaths = @()

    if ($PlayniteApi -and $PlayniteApi.Paths)
    {
        foreach ($propertyName in @("ExtensionsDataPath", "ConfigurationPath"))
        {
            if ($PlayniteApi.Paths.PSObject.Properties.Name -contains $propertyName)
            {
                $candidatePaths += $PlayniteApi.Paths.$propertyName
            }
        }
    }

    $documentsPath = Join-Path $env:USERPROFILE "Documents\PCVRCentralMatcher"
    $candidatePaths += $documentsPath

    foreach ($path in $candidatePaths)
    {
        if (-not [string]::IsNullOrWhiteSpace($path))
        {
            return $path
        }
    }

    return $PSScriptRoot
}

function Get-PCVRCentralCatalogPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory

    if (-not (Test-Path $dataDirectory))
    {
        New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
    }

    return Join-Path $dataDirectory "PCVRCentral_Gamelist.csv"
}

function Get-PCVRCentralModlistPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory

    if (-not (Test-Path $dataDirectory))
    {
        New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
    }

    return Join-Path $dataDirectory "PCVRCentral_Modlist.csv"
}

function Get-PCVRCentralModlistOldPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory

    if (-not (Test-Path $dataDirectory))
    {
        New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
    }

    return Join-Path $dataDirectory "PCVRCentral_Modlist_Old.csv"
}

function Get-PCVRCentralGamelistOldPath
{
    $dataDirectory = Get-PCVRCentralDataDirectory

    if (-not (Test-Path $dataDirectory))
    {
        New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
    }

    return Join-Path $dataDirectory "PCVRCentral_Gamelist_Old.csv"
}

function Get-PCVRCentralModlistUpdatePath
{
    $dataDirectory = Get-PCVRCentralDataDirectory

    if (-not (Test-Path $dataDirectory))
    {
        New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
    }

    return Join-Path $dataDirectory "PCVRCentral_Modlist_update.csv"
}

function Save-PCVRCentralGamelist
{
    $catalog = Get-GameCatalog
    $outputPath = Get-PCVRCentralCatalogPath

    if (Test-Path $outputPath)
    {
        $oldPath = Get-PCVRCentralGamelistOldPath

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

function Save-PCVRCentralModlistUpdate
{
    $newPath = Get-PCVRCentralCatalogPath
    $oldPath = Get-PCVRCentralGamelistOldPath
    $updatePath = Get-PCVRCentralModlistUpdatePath

    if (-not (Test-Path $newPath))
    {
        $newPath = Save-PCVRCentralGamelist
    }

    $newItems = Import-Csv -Path $newPath -Delimiter ';' -Encoding UTF8
    $changes = @()

    if (-not (Test-Path $oldPath))
    {
        foreach ($item in $newItems)
        {
            $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName") { [string]$item.NormalizedName } else { Normalize-GameName -Name ([string]$item.Name) }

            $changes += [PSCustomObject]@{
                NormalizedName = $normalizedName
                Name = [string]$item.Name
                OldMethodCount = 0
                NewMethodCount = [int]$item.MethodCount
                OldUrl = ""
                NewUrl = [string]$item.Url
            }
        }
    }
    else
    {
        $oldItems = Import-Csv -Path $oldPath -Delimiter ';' -Encoding UTF8
        $oldByKey = @{}

        foreach ($item in $oldItems)
        {
            $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName") { [string]$item.NormalizedName } else { Normalize-GameName -Name ([string]$item.Name) }

            $oldByKey[$normalizedName] = [PSCustomObject]@{
                NormalizedName = $normalizedName
                Name = [string]$item.Name
                Url = [string]$item.Url
                MethodCount = [int]$item.MethodCount
            }
        }

        foreach ($item in $newItems)
        {
            $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName") { [string]$item.NormalizedName } else { Normalize-GameName -Name ([string]$item.Name) }

            $oldItem = $null
            if ($oldByKey.ContainsKey($normalizedName))
            {
                $oldItem = $oldByKey[$normalizedName]
            }

            if (-not $oldItem)
            {
                $changes += [PSCustomObject]@{
                    NormalizedName = $normalizedName
                    Name = [string]$item.Name
                    OldMethodCount = 0
                    NewMethodCount = [int]$item.MethodCount
                    OldUrl = ""
                    NewUrl = [string]$item.Url
                }
                continue
            }

            if ([int]$oldItem.MethodCount -ne [int]$item.MethodCount)
            {
                $changes += [PSCustomObject]@{
                    NormalizedName = $normalizedName
                    Name = [string]$item.Name
                    OldMethodCount = [int]$oldItem.MethodCount
                    NewMethodCount = [int]$item.MethodCount
                    OldUrl = [string]$oldItem.Url
                    NewUrl = [string]$item.Url
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
        $CsvPath = Get-PCVRCentralCatalogPath
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
        $normalizedName = if ($item.PSObject.Properties.Name -contains "NormalizedName") { [string]$item.NormalizedName } else { Normalize-GameName -Name $nameValue }

        $result += [PSCustomObject]@{
            NormalizedName = $normalizedName
            Name = $nameValue
            Url = [string]$item.Url
            MethodCount = [int]$item.MethodCount
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

    $urls = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

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

function Get-FullDetailsRows
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $section = Get-FullDetailsSection -Html $Html

    $rows = @()

    $rowMatches = [regex]::Matches(
        $section,
        '(?is)<(?:tr|div|li|p|span)[^>]*>(.*?)</(?:tr|div|li|p|span)>'
    )

    foreach ($match in $rowMatches)
    {
        $rowText = Clean-HTMLText -Text $match.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($rowText))
        {
            $rows += $rowText
        }
    }

    return $rows
}

function Get-DetailRowValue
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $rows = Get-FullDetailsRows -Html $Html

    foreach ($row in $rows)
    {
        if ([string]::IsNullOrWhiteSpace($row))
        {
            continue
        }

        if ($row -imatch "^(?<label>Framework|Motion controls|Motion control)\s*(?:[:\-]|[\s]{1,})+(?<value>.+)$")
        {
            $labelFound = $Matches["label"].Trim()
            $valueFound = $Matches["value"].Trim()

            if ($labelFound -ieq $Label -and -not [string]::IsNullOrWhiteSpace($valueFound))
            {
                return $valueFound
            }
        }
    }

    return ""
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

        return [PSCustomObject]@{
            Framework = [string]$framework
            MotionControl = [string]$motion
        }
    }
    catch
    {
        Write-Warning "Mod page could not be loaded: $ModPageUrl"
        return [PSCustomObject]@{
            Framework = ""
            MotionControl = ""
        }
    }
}

function Save-PCVRCentralModlist
{
    $catalog = Import-PCVRCentralGamelist
    $outputPath = Get-PCVRCentralModlistPath
    $oldPath = Get-PCVRCentralModlistOldPath
    $updatePath = Get-PCVRCentralModlistUpdatePath

    if (Test-Path $outputPath)
    {
        if (Test-Path $oldPath)
        {
            Remove-Item -Path $oldPath -Force -ErrorAction SilentlyContinue
        }

        Move-Item -Path $outputPath -Destination $oldPath -Force -ErrorAction Stop
    }

    $selectedNormalizedNames = @()

    if (Test-Path $updatePath)
    {
        $updateItems = Import-Csv -Path $updatePath -Delimiter ';' -Encoding UTF8

        foreach ($item in $updateItems)
        {
            $normalized = if ($item.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$item.NormalizedName)) {
                [string]$item.NormalizedName
            }
            elseif ($item.PSObject.Properties.Name -contains "Name") {
                Normalize-GameName -Name ([string]$item.Name)
            }
            else {
                ""
            }

            if (-not [string]::IsNullOrWhiteSpace($normalized))
            {
                $selectedNormalizedNames += $normalized
            }
        }
    }

    if ($selectedNormalizedNames.Count -eq 0)
    {
        $gamesToProcess = @($catalog | Where-Object { $_.MethodCount -gt 0 })
    }
    else
    {
        $gamesToProcess = @($catalog | Where-Object { $selectedNormalizedNames -contains $_.NormalizedName })
    }

    $preservedRows = @()

    if (Test-Path $oldPath)
    {
        $oldRows = Import-Csv -Path $oldPath -Delimiter ';' -Encoding UTF8

        foreach ($row in $oldRows)
        {
            $normalized = if ($row.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace([string]$row.NormalizedName)) {
                [string]$row.NormalizedName
            }
            elseif ($row.PSObject.Properties.Name -contains "GameName") {
                Normalize-GameName -Name ([string]$row.GameName)
            }
            elseif ($row.PSObject.Properties.Name -contains "Name") {
                Normalize-GameName -Name ([string]$row.Name)
            }
            else {
                ""
            }

            if (-not [string]::IsNullOrWhiteSpace($normalized) -and $selectedNormalizedNames -notcontains $normalized)
            {
                $preservedRows += [PSCustomObject]@{
                    NormalizedName = $normalized
                    GameName = if ($row.PSObject.Properties.Name -contains "GameName") { [string]$row.GameName } else { [string]$row.Name }
                    MainGameUrl = if ($row.PSObject.Properties.Name -contains "MainGameUrl") { [string]$row.MainGameUrl } else { "" }
                    ModPageUrl = if ($row.PSObject.Properties.Name -contains "ModPageUrl") { [string]$row.ModPageUrl } else { "" }
                    Framework = if ($row.PSObject.Properties.Name -contains "Framework") { [string]$row.Framework } else { "" }
                    MotionControl = if ($row.PSObject.Properties.Name -contains "MotionControl") { [string]$row.MotionControl } else { "" }
                }
            }
        }
    }

    $newRows = @()

    foreach ($game in $gamesToProcess)
    {
        Write-Host "Processing: $($game.Name) ($($game.Url))"

        $modUrls = @()

        try
        {
            $modUrls = Get-GameModPageLinks -GameUrl $game.Url
        }
        catch
        {
            Write-Warning "Could not read mod links for game: $($game.Name) - $($game.Url)"
            $modUrls = @()
        }

        Write-Host "Mod URLs found: $($modUrls.Count)"

        foreach ($modUrl in $modUrls)
        {
            Write-Host "  $modUrl"

            try
            {
                $details = Get-ModPageDetails -ModPageUrl $modUrl

                $newRows += [PSCustomObject]@{
                    NormalizedName = [string]$game.NormalizedName
                    GameName = [string]$game.Name
                    MainGameUrl = [string]$game.Url
                    ModPageUrl = [string]$modUrl
                    Framework = [string]$details.Framework
                    MotionControl = [string]$details.MotionControl
                }
            }
            catch
            {
                Write-Warning "Skipping invalid mod page: $modUrl"
                continue
            }
        }
    }

    $finalRows = @($preservedRows + $newRows)

    if ($finalRows.Count -gt 0)
    {
        $finalRows |
            Select-Object NormalizedName, GameName, MainGameUrl, ModPageUrl, Framework, MotionControl |
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
        } |
            Select-Object NormalizedName, GameName, MainGameUrl, ModPageUrl, Framework, MotionControl |
            Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }

    return $outputPath
}

function Start-PCVRCentralSync
{
    param($args)

    try
    {
        $modTag = Ensure-TagExists -TagName "PCVR-Mod"
        $nativeTag = Ensure-TagExists -TagName "PCVR-Native"

        $csvPath = Save-PCVRCentralGamelist
        $catalog = Import-PCVRCentralGamelist -CsvPath $csvPath

        $modListUpdatePath = Save-PCVRCentralModlistUpdate
        $modListPath = Save-PCVRCentralModlist

        $updatedCount = 0

        foreach ($game in $PlayniteApi.Database.Games)
        {
            $normalized = Normalize-GameName -Name $game.Name
            $match = $catalog | Where-Object { $_.NormalizedName -eq $normalized } | Select-Object -First 1

            if (-not $match)
            {
                continue
            }

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
                $updatedCount++
            }
        }

        $message = "$($catalog.Count) Spiele auf PCVR Central gefunden`n$updatedCount Spiele in Playnite geupdatet"

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

Export-ModuleMember -Function Ensure-TagExists, Normalize-GameName, Get-GameCatalog, Get-PCVRCentralDataDirectory, Get-PCVRCentralCatalogPath, Get-PCVRCentralModlistPath, Get-PCVRCentralModlistOldPath, Get-PCVRCentralGamelistOldPath, Get-PCVRCentralModlistUpdatePath, Save-PCVRCentralGamelist, Save-PCVRCentralModlistUpdate, Import-PCVRCentralGamelist, Normalize-ModUrl, Is-ValidModPageUrl, Get-GameModPageLinks, Get-FullDetailsSection, Get-FullDetailsRows, Clean-HTMLText, Get-DetailRowValue, Get-ModPageDetails, Save-PCVRCentralModlist, GetMainMenuItems, Start-PCVRCentralSync