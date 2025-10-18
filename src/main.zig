const std = @import("std");
const builtin = @import("builtin");
const Client = @import("Client.zig");
const cmd = @import("cmd.zig");

pub const axe = @import("axe").Axe(.{
    .mutex = .{ .function = .progress_stderr },
});

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = axe.log,
};

pub const usage = blk: {
    var str: []const u8 =
        \\Usage: zpotify [--]<command> [options]
        \\
        \\Commands:
        \\
    ;
    for (std.meta.declarations(cmd)) |decl| {
        str = str ++ std.fmt.comptimePrint("  {s: <10}  {s}\n", .{
            decl.name,
            @field(cmd, decl.name).description,
        });
    }
    break :blk str;
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else if (builtin.link_libc)
        std.heap.c_allocator
    else
        std.heap.smp_allocator;

    // allocator used with ArenaAllocator
    const raw_allocator = if (builtin.mode == .Debug)
        allocator
    else if (builtin.link_libc)
        std.heap.raw_c_allocator
    else
        std.heap.page_allocator;

    defer if (builtin.mode == .Debug) {
        _ = debug_allocator.deinit();
    };

    axe.init(allocator, null, null) catch unreachable;
    defer axe.deinit(allocator);

    var args = std.process.args();
    std.debug.assert(args.skip());
    var command = args.next() orelse {
        try cmd.help.exec(null);
        std.process.exit(1);
    };

    if (std.mem.startsWith(u8, command, "--")) {
        command = command[2..];
    }

    if (std.mem.eql(u8, command, "logout")) {
        return cmd.logout.exec(allocator);
    } else if (std.mem.eql(u8, command, "help")) {
        return cmd.help.exec(args.next());
    } else if (std.mem.eql(u8, command, "version")) {
        return cmd.version.exec();
    } else if (std.mem.eql(u8, command, "completion")) {
        return cmd.completion.exec(args.next());
    }

    var client = try Client.init(allocator, raw_allocator);
    defer client.deinit();

    if (std.mem.eql(u8, command, "print")) {
        return cmd.print.exec(&client, &args);
    } else if (std.mem.eql(u8, command, "play")) {
        return cmd.play.exec(&client, raw_allocator, args.next());
    } else if (std.mem.eql(u8, command, "pause")) {
        return cmd.pause.exec(&client);
    } else if (std.mem.eql(u8, command, "prev")) {
        return cmd.prev.exec(&client);
    } else if (std.mem.eql(u8, command, "next")) {
        return cmd.next.exec(&client);
    } else if (std.mem.eql(u8, command, "repeat")) {
        return cmd.repeat.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "shuffle")) {
        return cmd.shuffle.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "seek")) {
        return cmd.seek.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "vol") or std.mem.eql(u8, command, "volume")) {
        return cmd.volume.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "like")) {
        return cmd.like.exec(&client);
    } else if (std.mem.eql(u8, command, "queue")) {
        return cmd.queue.exec(&client);
    } else if (std.mem.eql(u8, command, "devices")) {
        return cmd.devices.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "transfer")) {
        return cmd.transfer.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "waybar")) {
        return cmd.waybar.exec(&client, raw_allocator);
    } else {
        try cmd.help.exec(command);
        std.process.exit(1);
    }
}
