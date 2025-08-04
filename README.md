# zpotify
zpotify is a CLI for controlling Spotify playback and much more!

https://github.com/user-attachments/assets/5a97453a-db8a-4689-b2d0-ab1f2009fcb0

## Installation

### [AUR](https://aur.archlinux.org/packages/zpotify)

Using your favorite AUR helper or manually:
```
git clone https://aur.archlinux.org/zpotify
cd zpotify
makepkg -si
```

### Building

Requires zig 0.14.1, libjpeg and chafa.
```
git clone https://github.com/ratakor/zpotify
cd zpotify
zig build -Doptimize=ReleaseSafe
```
Zsh completions are available [here](_zpotify)!

## Usage
Requires Spotify premium.
```
Usage: zpotify [command] [options]

Commands:
  print      | Display current track info in a specific format
  search     | Search a track, playlist, album, or artist with a TUI
  play       | Play a track, playlist, album, or artist from your library
  pause      | Toggle pause state
  prev       | Skip to previous track
  next       | Skip to next track
  repeat     | Get/Set repeat mode
  shuffle    | Toggle shuffle mode
  seek       | Get/Set the position of the current track
  vol        | Get/Set volume or increase/decrease volume by 10%
  like       | Add the current track to your liked songs
  queue      | Display tracks in the queue
  devices    | List all available devices
  transfer   | Transfer playback to another device
  waybar     | Display infos about the current playback for a waybar module
  logout     | Remove the stored credentials from the config file
  help       | Display information about a command
  version    | Display program version
```

## Performance

More than 2x times faster than the only good alternative [baton](https://github.com/joshuathompson/baton)!
```
% cat run
#!/bin/sh
$1 play artist GPF
$1 next
$1 prev
$1 pause
$1 repeat
$1 shuffle
$1 vol down
% poop "./run baton" "./run zpotify" --duration 60000
Benchmark 1 (15 runs): ./run baton
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          4.18s  ± 88.4ms    3.99s  … 4.32s           0 ( 0%)        0%
  peak_rss           100.0MB ± 96.6KB   99.7MB …  100MB          1 ( 7%)        0%
  cpu_cycles         14.5G  ±  285M     14.1G  … 15.2G           1 ( 7%)        0%
  instructions       27.1G  ±  303M     26.5G  … 27.8G           0 ( 0%)        0%
  cache_references    330M  ± 11.9M      310M  …  353M           0 ( 0%)        0%
  cache_misses       75.2M  ± 4.46M     67.9M  … 84.4M           0 ( 0%)        0%
  branch_misses      40.8M  ±  512K     40.0M  … 41.7M           0 ( 0%)        0%
Benchmark 2 (43 runs): ./run zpotify
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          1.40s  ± 87.3ms    1.21s  … 1.64s           0 ( 0%)        ⚡- 66.5% ±  1.3%
  peak_rss           2.24MB ± 10.3KB    2.24MB … 2.28MB          9 (21%)        ⚡- 97.8% ±  0.0%
  cpu_cycles         2.11G  ± 98.1M     2.03G  … 2.38G           4 ( 9%)        ⚡- 85.5% ±  0.7%
  instructions       6.70G  ± 6.02K     6.70G  … 6.70G           1 ( 2%)        ⚡- 75.3% ±  0.3%
  cache_references    713K  ± 23.2K      675K  …  779K           0 ( 0%)        ⚡- 99.8% ±  1.1%
  cache_misses        193K  ± 31.6K      130K  …  275K           1 ( 2%)        ⚡- 99.7% ±  1.8%
  branch_misses      5.97M  ± 1.93M     4.60M  … 11.4M           6 (14%)        ⚡- 85.4% ±  2.5%
```

## Credits
- [baton](https://github.com/joshuathompson/baton)
- [zig-spoon](https://git.sr.ht/~leon_plickat/zig-spoon)
- [chafa](https://github.com/hpjansson/chafa)

## TODO
- add `zpotify play liked` cmd which play liked songs
- add a way to save track / album to a playlist
- embed [librespot](https://github.com/librespot-org/librespot)
  - need to create bindings
  - use [build.crab](https://github.com/akarpovskii/build.crab) for build integration
  - use [ziggy](https://github.com/kristoff-it/ziggy) for config
  - librespot alternative?: [cspot](https://github.com/feelfreelinux/cspot)
- add man page with [zzdoc](https://github.com/rockorager/zzdoc)
- redo the perf analysis
- add test coverage
- add a tui like `search` for `queue` to edit the queue
