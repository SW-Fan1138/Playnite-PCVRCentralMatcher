# PCVR Central Matcher

A Playnite script extension that synchronizes your library with PCVR Central.

## Features

- Matches your Playnite library against the PCVR Central catalog
- Adds a "PCVR Central" link to supported games
- Tags games requiring VR mods with `PCVR-Mod`
- Tags games with built-in VR support with `PCVR-Native`
- Automatically removes incorrect VR tags during synchronization
- Safe to run multiple times

## Requirements

Create the following Playnite tags before using the extension:

- PCVR-Mod
- PCVR-Native

## Installation

1. Download the latest release.
2. Extract the extension into:

   ```
   %appdata%\Playnite\Extensions\
   ```

3. Restart Playnite.
4. Create the required tags:
   - PCVR-Mod
   - PCVR-Native

## Usage

Open:

```
Main Menu → PCVR Central Matcher: Sync
```

The extension will:

- Download the PCVR Central catalog
- Match games against your Playnite library
- Add a "PCVR Central" link
- Apply the correct VR tag:
  - PCVR-Mod
  - PCVR-Native

## Tags

### PCVR-Mod

Games that require a VR modification.

Examples:

- Cyberpunk 2077
- Ready or Not
- Alien: Isolation

### PCVR-Native

Games with built-in PCVR support.

Examples:

- VRChat
- War Thunder
- Euro Truck Simulator 2

## Development

This project was created collaboratively by the author and Microsoft Copilot (GPT-5).

The author defined the feature set, performed all testing and validation, and made all release decisions. Microsoft Copilot assisted with code generation, troubleshooting, refactoring, and documentation.

Every release is manually reviewed and tested before publication.

## Credits

PCVR Central

https://pcvrcentral.com

Playnite

https://playnite.link

## License

MIT License
