const std = @import("std");

const LOG_CAP = 4096;
var syscall_log: [LOG_CAP]u8 = undefined;
var syscall_log_pos: usize = 0;

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch return;

    const n = @min(msg.len, LOG_CAP - syscall_log_pos);
    @memcpy(syscall_log[syscall_log_pos .. syscall_log_pos + n], msg[0..n]);
    syscall_log_pos += n;
}
