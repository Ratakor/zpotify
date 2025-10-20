// when adding a new command make sure to add it to
// - src/main.zig (main())
// - src/cmd.zig (here)
// - src/cmd/completion.zig (if needing specific completion)
// - README.md (Usage)

pub const get = @import("cmd/get.zig");
pub const print = @import("cmd/print.zig");
pub const search = @import("cmd/search.zig");
pub const play = @import("cmd/play.zig");
pub const pause = @import("cmd/pause.zig");
pub const prev = @import("cmd/prev.zig");
pub const next = @import("cmd/next.zig");
pub const repeat = @import("cmd/repeat.zig");
pub const shuffle = @import("cmd/shuffle.zig");
pub const seek = @import("cmd/seek.zig");
pub const volume = @import("cmd/volume.zig");
pub const like = @import("cmd/like.zig");
pub const queue = @import("cmd/queue.zig");
pub const devices = @import("cmd/devices.zig");
pub const transfer = @import("cmd/transfer.zig");
pub const waybar = @import("cmd/waybar.zig");
pub const logout = @import("cmd/logout.zig");
pub const completion = @import("cmd/completion.zig");
pub const help = @import("cmd/help.zig");
pub const version = @import("cmd/version.zig");
