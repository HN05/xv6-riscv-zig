const std = @import("std");
const param = @import("common").param;
const ad = @import("address.zig");

pub const console_major = 1;
pub const disk_major = 2;

pub const ID = packed struct(u32) {
    const total_bits = @bitSizeOf(u32);
    pub const minor_bit_size = total_bits - major_bit_size;
    pub const major_bit_size = std.math.log2_int_ceil(usize, param.device_number);

    minor: std.meta.Int(.unsigned, minor_bit_size),
    major: std.meta.Int(.unsigned, major_bit_size),

    pub const root_fs_device = @This(){ .major = disk_major, .minor = 1 };
};

const Device = @This();

// map major device number to device functions.
// addr kind, address, number
read: fn (comptime ad.AddressKind, usize, usize) ReadErrors!usize,
write: fn (comptime ad.AddressKind, usize, usize) WriteErrors!usize,

pub var deviceTable: [param.device_number]Device = undefined;

pub const ReadErrors = error{ ProcessKilled, NoRunningProcess };
pub const WriteErrors = error{};
