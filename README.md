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
Usage: zpotify [command] [options]

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
  waybar     | Display infos about the current playback for a waybar module
  logout     | Remove the stored credentials from the config file
  help       | Display information about a command
  version    | Display program version
```

## Performance

```
% cat run_all
#!/bin/sh
$1 play playlist music
$1 next
$1 prev
$1 pause
$1 repeat
$1 shuffle
$1 vol up
% poop "./run_all zpotify" "./run_all baton" --duration 60000
Benchmark 1 (22 runs): ./run_all zpotify
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          2.77s  ±  134ms    2.59s  … 3.08s           0 ( 0%)        0%
  peak_rss           2.34MB ± 25.7KB    2.33MB … 2.42MB          4 (18%)        0%
  cpu_cycles         2.12G  ±  100M     1.95G  … 2.33G           0 ( 0%)        0%
  instructions       6.63G  ±  525K     6.62G  … 6.63G           4 (18%)        0%
  cache_references    989K  ± 54.6K      904K  … 1.11M           0 ( 0%)        0%
  cache_misses        404K  ± 18.2K      345K  …  441K           1 ( 5%)        0%
  branch_misses      7.89M  ± 1.72M     5.36M  … 12.4M           0 ( 0%)        0%
Benchmark 2 (11 runs): ./run_all baton
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          5.96s  ±  413ms    4.87s  … 6.43s           1 ( 9%)        💩+114.8% ±  7.0%
  peak_rss           100.0MB ± 58.4KB   99.9MB …  100MB          0 ( 0%)        💩+4164.7% ±  1.3%
  cpu_cycles         15.4G  ±  525M     14.6G  … 16.3G           0 ( 0%)        💩+628.0% ± 11.0%
  instructions       27.2G  ±  308M     26.7G  … 27.6G           0 ( 0%)        💩+310.5% ±  2.0%
  cache_references    346M  ± 14.1M      325M  …  369M           0 ( 0%)        💩+34890.7% ± 612.1%
  cache_misses       90.3M  ± 6.71M     82.4M  …  103M           0 ( 0%)        💩+22250.8% ± 710.6%
  branch_misses      42.0M  ±  857K     40.9M  … 43.2M           0 ( 0%)        💩+432.7% ± 14.3%
```

## TODO
- add `playlists` (Display a list of your playlists (e.g. for use with play and dmenu)
- add `search` (TUI like [baton](https://github.com/joshuathompson/baton)?)
- add tests
