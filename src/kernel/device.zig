const std = @import("std");
const param = @import("common").param;
const ad = @import("address.zig");

fn MakeDeviceID(comptime ndev: comptime_int) type {
    const total_bits = @bitSizeOf(usize);
    const major_bits = std.math.log2_int_ceil(usize, ndev);
    const minor_bits = total_bits - major_bits;

    return packed struct(usize) {
        minor: std.meta.Int(.unsigned, minor_bits),
        major: std.meta.Int(.unsigned, major_bits),
    };
}

pub const ID = MakeDeviceID(param.NDEV);
pub const console_major = 1;
const Device = @This();

pub const ReadErrors = error { ProcessKilled, NoRunningProcess };
pub const WriteErrors = error {};

// map major device number to device functions.
// addr kind, address, number
read: fn (comptime ad.AddressKind, usize, usize) ReadErrors!usize,
write: fn (comptime ad.AddressKind, usize, usize) WriteErrors!usize,

pub var deviceTable: [param.NDEV]Device = undefined;
