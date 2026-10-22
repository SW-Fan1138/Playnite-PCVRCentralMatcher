function Start-PCVRCentralSync
{
    param($args)

    try
    {
        #
        # Get required Playnite tags
        #
        $ModTag = $PlayniteApi.Database.Tags | Where-Object {
            $_.Name -eq "PCVR-Mod"
        }

        $NativeTag = $PlayniteApi.Database.Tags | Where-Object {
            $_.Name -eq "PCVR-Native"
        }

        if (-not $ModTag)
        {
            $PlayniteApi.Dialogs.ShowErrorMessage(
                "Required tag 'PCVR-Mod' was not found."
            )
            return
        }

        if (-not $NativeTag)
        {
            $PlayniteApi.Dialogs.ShowErrorMessage(
                "Required tag 'PCVR-Native' was not found."
            )
            return
        }

        #
        # Download PCVR Central game catalog
        #
        $client = New-Object System.Net.WebClient
        $client.Encoding = [System.Text.Encoding]::UTF8

        $html = $client.DownloadString(
            "https://pcvrcentral.com/games"
        )

        #
        # Extract game slug, game name and method count
        #
        $matches = [regex]::Matches(
            $html,
            '<a[^>]*href="/games/([^"]+)"[^>]*>.*?<span class="truncate">([^<]+)</span>.*?<span class="shrink-0 text-xs text-muted-foreground">([0-9]+)\s+method',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        #
        # Build lookup table
        #
        $pcvrGames = @{}

        foreach ($match in $matches)
        {
            $slug = $match.Groups[1].Value.Trim()
            $name = $match.Groups[2].Value.Trim()
            $methodCount = [int]$match.Groups[3].Value

            $normalized = (
                $name.ToLowerInvariant() `
                -replace '[^a-z0-9]', ''
            )

            $pcvrGames[$normalized] = [PSCustomObject]@{
                Url = "https://pcvrcentral.com/games/$slug"
                MethodCount = $methodCount
            }
        }

        $UpdatedCount = 0

        #
        # Process Playnite library
        #
        foreach ($game in $PlayniteApi.Database.Games)
        {
            $normalized = (
                $game.Name.ToLowerInvariant() `
                -replace '[^a-z0-9]', ''
            )

            if (-not $pcvrGames.ContainsKey($normalized))
            {
                continue
            }

            $entry = $pcvrGames[$normalized]

            $changed = $false

            #
            # Ensure TagIds collection exists
            #
            if (-not $game.TagIds)
            {
                $game.TagIds = New-Object System.Collections.Generic.List[Guid]
            }

            #
            # Native VR game
            #
            if ($entry.MethodCount -eq 0)
            {
                if (-not $game.TagIds.Contains($NativeTag.Id))
                {
                    $game.TagIds.Add($NativeTag.Id)
                    $changed = $true
                }

                if ($game.TagIds.Contains($ModTag.Id))
                {
                    $game.TagIds.Remove($ModTag.Id)
                    $changed = $true
                }
            }
            #
            # VR mod required
            #
            else
            {
                if (-not $game.TagIds.Contains($ModTag.Id))
                {
                    $game.TagIds.Add($ModTag.Id)
                    $changed = $true
                }

                if ($game.TagIds.Contains($NativeTag.Id))
                {
                    $game.TagIds.Remove($NativeTag.Id)
                    $changed = $true
                }
            }

            #
            # Check whether a PCVR Central link already exists
            #
            $linkExists = $false

            if ($game.Links)
            {
                foreach ($link in $game.Links)
                {
                    if ($link.Name -eq "PCVR Central")
                    {
                        $linkExists = $true
                        break
                    }
                }
            }
            else
            {
                $game.Links = New-Object "System.Collections.ObjectModel.ObservableCollection[Playnite.SDK.Models.Link]"
            }

            #
            # Add PCVR Central link
            #
            if (-not $linkExists)
            {
                $newLink = New-Object Playnite.SDK.Models.Link(
                    "PCVR Central",
                    $entry.Url
                )

                $game.Links.Add($newLink)
                $changed = $true
            }

            #
            # Save game if changes were made
            #
            if ($changed)
            {
                $PlayniteApi.Database.Games.Update($game)
                $UpdatedCount++
            }
        }

        $PlayniteApi.Dialogs.ShowMessage(
            "$UpdatedCount games were updated.",
            "PCVR Central Matcher"
        )
    }
    catch
    {
        $PlayniteApi.Dialogs.ShowErrorMessage(
            $_.Exception.ToString(),
            "PCVR Central Matcher"
        )
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

Export-ModuleMember -Function GetMainMenuItems, Start-PCVRCentralSync
