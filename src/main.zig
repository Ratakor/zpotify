const std = @import("std");
const builtin = @import("builtin");
const api = @import("zpotify");
const cmd = @import("cmd.zig");
const save = @import("save.zig");

pub const axe = @import("axe").Axe(.{});

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
        if (std.mem.eql(u8, decl.name, "Context")) continue;
        str = str ++ std.fmt.comptimePrint("  {s: <10}  {s}\n", .{
            decl.name,
            @field(cmd, decl.name).description,
        });
    }
    break :blk str;
};

const redirect_uri = "http://127.0.0.1:9999/callback";
const scopes = [_]api.Scope{
    .user_read_currently_playing,
    .user_read_playback_state,
    .user_modify_playback_state,
    .user_library_modify,
    .user_library_read,
    .user_follow_read,
    .user_follow_modify,
    .playlist_read_private,
    .playlist_modify_public,
    .playlist_modify_private,
};

pub fn main(init: std.process.Init) !void {
    var ctx: cmd.Context = .{
        .io = init.io,
        .allocator = init.gpa,
        .arena = init.arena,
        .env_map = init.environ_map,
        .args = init.minimal.args.iterate(),
        .client = undefined,
    };

    try axe.init(ctx.io, null, ctx.env_map);
    defer axe.deinit();

    std.debug.assert(ctx.args.skip());
    var command = ctx.args.next() orelse {
        try cmd.help.exec(&ctx, null);
        std.process.exit(1);
    };

    if (std.mem.startsWith(u8, command, "--")) {
        command = command[2..];
    }

    if (std.mem.eql(u8, command, "logout")) {
        return cmd.logout.exec(&ctx);
    } else if (std.mem.eql(u8, command, "help")) {
        return cmd.help.exec(&ctx, ctx.args.next());
    } else if (std.mem.eql(u8, command, "version")) {
        return cmd.version.exec(&ctx);
    } else if (std.mem.eql(u8, command, "completion")) {
        return cmd.completion.exec(&ctx);
    }

    const save_path = try save.getPath(ctx.allocator, ctx.env_map);
    defer ctx.allocator.free(save_path);
    var client = try api.Client.init(
        redirect_uri,
        &scopes,
        ctx.io,
        ctx.allocator,
        ctx.arena,
        save_path,
    );
    ctx.client = &client; // TODO: unnecessary
    defer client.deinit();

    if (std.mem.eql(u8, command, "print")) {
        return cmd.print.exec(&ctx);
    } else if (std.mem.eql(u8, command, "play")) {
        return cmd.play.exec(&ctx);
    } else if (std.mem.eql(u8, command, "pause")) {
        return cmd.pause.exec(&ctx);
    } else if (std.mem.eql(u8, command, "prev")) {
        return cmd.prev.exec(&ctx);
    } else if (std.mem.eql(u8, command, "next")) {
        return cmd.next.exec(&ctx);
    } else if (std.mem.eql(u8, command, "repeat")) {
        return cmd.repeat.exec(&ctx);
    } else if (std.mem.eql(u8, command, "shuffle")) {
        return cmd.shuffle.exec(&ctx);
    } else if (std.mem.eql(u8, command, "seek")) {
        return cmd.seek.exec(&ctx);
    } else if (std.mem.eql(u8, command, "vol") or std.mem.eql(u8, command, "volume")) {
        return cmd.volume.exec(&ctx);
    } else if (std.mem.eql(u8, command, "like")) {
        return cmd.like.exec(&ctx);
    } else if (std.mem.eql(u8, command, "queue")) {
        return cmd.queue.exec(&ctx);
    } else if (std.mem.eql(u8, command, "devices")) {
        return cmd.devices.exec(&ctx);
    } else if (std.mem.eql(u8, command, "transfer")) {
        return cmd.transfer.exec(&ctx);
    } else {
        try cmd.help.exec(&ctx, command);
        std.process.exit(1);
    }
}

test {
    std.testing.refAllDecls(@This());
}
