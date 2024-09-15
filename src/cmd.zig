// when adding a new command make sure to add it to
// - src/cmd/help.zig
// - src/main.zig (usage + main())
// - src/cmd.zig
// - _zpotify (main_commands + help)
// - README.md

pub const print = @import("cmd/print.zig");
pub const search = @import("cmd/search.zig");
pub const play = @import("cmd/play.zig");
pub const pause = @import("cmd/pause.zig");
pub const prev = @import("cmd/prev.zig");
pub const next = @import("cmd/next.zig");
pub const repeat = @import("cmd/repeat.zig");
pub const shuffle = @import("cmd/shuffle.zig");
pub const seek = @import("cmd/seek.zig");
pub const vol = @import("cmd/vol.zig");
pub const like = @import("cmd/like.zig");
pub const devices = @import("cmd/devices.zig");
pub const transfer = @import("cmd/transfer.zig");
pub const waybar = @import("cmd/waybar.zig");
pub const logout = @import("cmd/logout.zig");
pub const help = @import("cmd/help.zig");
pub const version = @import("cmd/version.zig");
