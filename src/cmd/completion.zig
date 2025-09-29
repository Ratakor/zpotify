const std = @import("std");
const cmd = @import("../cmd.zig");

pub const description = "Generate shell completion script";
pub const usage =
    \\Usage: zpotify completion <shell>
    \\
    \\Description: Generate shell completion script for the specified shell
    \\
    \\Supported shells: bash zsh
    \\
;

const Shell = enum {
    bash,
    zsh,

    fn completion(self: Shell) []const u8 {
        return switch (self) {
            .bash => bash_completion,
            .zsh => zsh_completion,
        };
    }
};

pub fn exec(optional_shell: ?[]const u8) !void {
    const shell_str = optional_shell orelse {
        try cmd.help.exec("completion");
        std.process.exit(1);
    };

    const shell = std.meta.stringToEnum(Shell, shell_str) orelse {
        std.log.err("Unsupported shell: {s}", .{shell_str});
        try cmd.help.exec("completion");
        std.process.exit(1);
    };

    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(shell.completion());
}

// TODO!
const bash_completion = blk: {
    // const decls = std.meta.declarations(cmd);
    var str: []const u8 =
        \\_zpotify_module()
        \\{
        \\
    ;
    str = str ++
        \\}
        \\complete -F _zpotify_module zpotify
        \\
    ;
    break :blk str;
};

const zsh_completion = blk: {
    const decls = std.meta.declarations(cmd);
    var str: []const u8 =
        \\#compdef zpotify
        \\_zpotify() {
        \\    local state line
        \\    _arguments -s \
        \\        '1: :->cmd' \
        \\        '*: :->args'
        \\
        \\    case $state in
        \\    cmd)
        \\        main_commands=('
    ;
    for (decls) |decl| {
        str = str ++ (decl.name ++ "\\:\"" ++ @field(cmd, decl.name).description ++ "\" ");
    }
    str = str ++ "')\n" ++
        \\        main_commands=($main_commands)
        \\        _alternative "args:command:(($main_commands))"
        \\        ;;
        \\    args)
        \\        case $line[1] in
        \\        print)
        \\            format_options=('{title}\:"prints the title of the current track" {state}\:"prints the current playback state" {album}\:"prints the name of the current album" {artist}\:"prints the name of the first artist of the current track" {artists}\:"prints all artists" {device}\:"prints the name of the current device" {volume}\:"prints the current volume" {repeat}\:"prints the current repeat state" {shuffle}\:"prints the current shuffle state" {bar\\\:50}\:"prints a progress bar" {progress}\:"prints the current progress as min:sec" {duration}\:"prints the duration of the current track as min:sec" {url}\:"prints the URL of the current track" {image}\:"prints the URL of the current track album cover" {icon}\:"prints the URL of the current track album cover with the smallest size"')
        \\            format_options=($format_options)
        \\            _arguments -s "*:format:(($format_options))"
        \\            ;;
        \\        play|search)
        \\            _arguments -s "2:query_type:(track playlist album artist)"
        \\            ;;
        \\        repeat)
        \\            _arguments -s "2:repeat_mode:(track context off)"
        \\            ;;
        \\        seek)
        \\            _arguments -s "2:seconds:(0:00 $(zpotify print {duration} 2>/dev/null))"
        \\            ;;
        \\        vol|volume)
        \\            _arguments -s "2:volume:(up down $(zpotify print {volume} 2>/dev/null))"
        \\            ;;
        \\        transfer)
        \\            devices=$(zpotify devices _name 2>/dev/null)
        \\            _arguments -s "2:device:(($devices))"
        \\            ;;
        \\        completion)
        \\            _arguments -s "2:shell:(bash zsh)"
        \\            ;;
        \\        help)
        \\            _arguments -s "2:commands:(
    ;
    for (decls) |decl| {
        str = str ++ (decl.name ++ " ");
    }
    str = str ++ ")\"\n" ++
        \\            ;;
        \\        esac
        \\        ;;
        \\    esac
        \\}
        \\
    ;
    break :blk str;
};
