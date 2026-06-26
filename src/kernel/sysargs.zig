const std = @import("std");
const log = @import("klog.zig");
const mem = @import("memory.zig");
const ad = @import("address.zig");

pub const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/stat.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/proc.h");
    @cInclude("kernel/fs.h");
    @cInclude("kernel/sleeplock.h");
    @cInclude("kernel/file.h");
    @cInclude("kernel/fcntl.h");
});

const InputRegister = enum { a0, a1, a2, a3, a4, a5 };
pub const errorVal = ~@as(u64, 0);

pub fn getInt(register: InputRegister) usize {
    const process = c.myproc();
    const result = switch (register) {
        .a0 => process.*.trapframe.*.a0,
        .a1 => process.*.trapframe.*.a1,
        .a2 => process.*.trapframe.*.a2,
        .a3 => process.*.trapframe.*.a3,
        .a4 => process.*.trapframe.*.a4,
        .a5 => process.*.trapframe.*.a5,
    };
    return @intCast(result);
}

const AddressNullErr = error{IsNull};

// Retrieve an argument as a pointer.
// Doesn't check for legality, since
// copyin/copyout will do that.
pub fn getAddress(register: InputRegister) ?ad.UserAddr {
    const int = getInt(register);
    if (int == 0) return null;
    return .fromInt(int);
}

// Fetch the nth word-sized system call argument as a null-terminated string.
// Copies into buf, at most max.
// Returns string length if OK (including nul), -1 if error.
pub fn getString(register: InputRegister, buffer: []u8) !usize {
    const address = getAddress(register);
    if (address) |a| {
        return try getStringFromAddres(a, buffer);
    }
    return AddressNullErr.IsNull;
}

const GetFileErrors = error{ OutOfRange, NotCreated };

pub fn getFile(register: InputRegister) GetFileErrors!*c.struct_file {
    var file: *c.struct_file = undefined;
    _ = try getFileAndDescriptor(register, &file);
    return file;
}

// Fetch the nth word-sized system call argument as a file descriptor
// and return both the descriptor and the corresponding struct file.
pub fn getFileAndDescriptor(register: InputRegister, fileDestination: ?**c.struct_file) GetFileErrors!usize {
    const fd = getInt(register);
    if (fd >= c.NOFILE) {
        return GetFileErrors.OutOfRange;
    }

    const files: *[c.NOFILE][*c]c.struct_file = &c.myproc().*.ofile;
    const file = files.*[fd] orelse {
        return GetFileErrors.NotCreated;
    };

    if (fileDestination) |dest| {
        dest.* = file;
    }

    return fd;
}

const FileDescriptorAllocateErrors = error{OutOfSpace};

// Allocate a file descriptor for the given file.
// Takes over file reference from caller on success.
pub fn fileDescriptorAllocate(file: *c.struct_file) FileDescriptorAllocateErrors!usize {
    const files: *[c.NOFILE][*c]c.struct_file = &c.myproc().*.ofile;

    var fd: usize = 0;
    while (fd < c.NOFILE) : (fd += 1) {
        if (files.*[fd] == null) {
            files.*[fd] = file;
            return fd;
        }
    }
    return FileDescriptorAllocateErrors.OutOfSpace;
}

const FetchAddressErrors = error{ AddressOutOfBounds, FailedCopyInToKernel };

fn getProcPageTable() ad.PageTablePtr {
    const process = c.myproc();
    return @alignCast(@ptrCast(process.*.pagetable));
}

// Fetch the pointer at addr from the current process.
pub fn fetchAddr(address: ad.UserAddr, destination: *ad.UserAddr) FetchAddressErrors!void {
    const process = c.myproc();

    // double comparison in case of overflow
    if (address.toInt() >= process.*.sz or address.toInt() + @sizeOf(*anyopaque) > process.*.sz) {
        return FetchAddressErrors.AddressOutOfBounds;
    }

    mem.copyIn(getProcPageTable(), std.mem.asBytes(&destination.value), address) catch return FetchAddressErrors.FailedCopyInToKernel;
}

// Fetch the nul-terminated string at addr from the current process.
// Returns length of string, not including nul 
// may not include null terminator
pub fn getStringFromAddres(address: ad.UserAddr, buffer: []u8) !usize {
    const pageTable = getProcPageTable();
    return mem.copyInString(pageTable, buffer, address);
}
