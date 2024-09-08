# zpotify
zpotify is a CLI for controlling Spotify playback and much more!

## Installation

### [AUR](https://aur.archlinux.org/packages/zpotify-bin)

```
git clone https://aur.archlinux.org/zpotify-bin.git
cd zpotify-bin
makepkg -si
```

### Manual Installation

Grab one of the [release](https://github.com/Ratakor/zpotify/releases)
according to your system. Zsh completions are available [here](_zpotify)!

### Building

Requires zig 0.13.0.
```
git clone https://github.com/ratakor/zpotify.git
cd zpotify
zig build -Doptimize=ReleaseSafe
```

## Usage
```
Usage: zpotify [command] [option]

Commands:
  print      | Display current track info in a specific format
  play       | Play a track, playlist, album, or artist
  pause      | Toggle pause state
  prev       | Skip to previous track
  next       | Skip to next track
  repeat     | Get/Set repeat mode
  shuffle    | Toggle shuffle mode
  seek       | Get/Set the position of the current track
  vol        | Get/Set volume or increase/decrease volume by 10%
  like       | Add the current track to your liked songs
  logout     | Remove the stored credentials from the config file
  help       | Display information about a command
  version    | Display program version
```

## TODO
- add a daemon mode
- add `playlists` (Display a list of your playlists (e.g. for use with play and dmenu)
- add `search` (TUI like [baton](https://github.com/joshuathompson/baton)?)
- add tests
