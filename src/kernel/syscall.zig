const std = @import("std");
const log = @import("klog.zig");
const procsyscalls = @import("sysproc.zig");
const ringbuf = @import("ringbuf.zig");

const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/proc.h");
    @cInclude("kernel/syscall.h");
    @cInclude("kernel/defs.h");
});

// Prototypes for the functions that handle system calls.
extern fn sys_fstat() u64;
extern fn sys_chdir() u64;
extern fn sys_dup() u64;
extern fn sys_read() u64;
extern fn sys_open() u64;
extern fn sys_write() u64;
extern fn sys_mknod() u64;
extern fn sys_unlink() u64;
extern fn sys_link() u64;
extern fn sys_mkdir() u64;
extern fn sys_close() u64;
extern fn sys_pipe() u64;
extern fn sys_exec() u64;

pub const SyscallNum = enum(usize) {
    SYS_fork = 1,
    SYS_exit = 2,
    SYS_wait = 3,
    SYS_pipe = 4,
    SYS_read = 5,
    SYS_kill = 6,
    SYS_exec = 7,
    SYS_fstat = 8,
    SYS_chdir = 9,
    SYS_dup = 10,
    SYS_getpid = 11,
    SYS_sbrk = 12,
    SYS_sleep = 13,
    SYS_uptime = 14,
    SYS_open = 15,
    SYS_write = 16,
    SYS_mknod = 17,
    SYS_unlink = 18,
    SYS_link = 19,
    SYS_mkdir = 20,
    SYS_close = 21,
    SYS_ringbuf = 22,
    _,
};

export fn syscall() void {
    const process = c.myproc();
    const num = process.*.trapframe.*.a7;

    const syscallNum: SyscallNum = @enumFromInt(num);

    const result: u64 = switch (syscallNum) {
        .SYS_exit => procsyscalls.sys_exit(),
        .SYS_close => sys_close(),
        .SYS_chdir => sys_chdir(),
        .SYS_dup => sys_dup(),
        .SYS_exec => sys_exec(),
        .SYS_fork => procsyscalls.sys_fork(),
        .SYS_fstat => sys_fstat(),
        .SYS_getpid => procsyscalls.sys_getpid(),
        .SYS_ringbuf => ringbuf.syscall(),
        .SYS_wait => procsyscalls.sys_wait(),
        .SYS_kill => procsyscalls.sys_kill(),
        .SYS_link => sys_link(),
        .SYS_mkdir => sys_mkdir(),
        .SYS_mknod => sys_mknod(),
        .SYS_open => sys_open(),
        .SYS_pipe => sys_pipe(),
        .SYS_read => sys_read(),
        .SYS_sbrk => procsyscalls.sys_sbrk(),
        .SYS_sleep => procsyscalls.sys_sleep(),
        .SYS_unlink => sys_unlink(),
        .SYS_uptime => procsyscalls.sys_uptime(),
        .SYS_write => sys_write(),
        else => ret: {
            log.print("{d} {s}: unkown sys call {d}\n", .{ process.*.pid, process.*.name, num });
            break :ret ~@as(usize, 0);
        },
    };

    process.*.trapframe.*.a0 = @intCast(result);
}


//  TODO: remove
// Fetch the uint64 at addr from the current process.
export fn fetchaddr(address: c.uint64, ip: *c.uint64) c_int {
    const process = c.myproc();

    if (address >= process.*.sz or address + @sizeOf(c.uint64) > process.*.sz) {
        return -1;
    }

    const result = c.copyin(process.*.pagetable, @ptrCast(ip), address, @sizeOf(c.uint64));
    if (result != 0) {
        return -1;
    }
    return 0;
}

// Fetch the nul-terminated string at addr from the current process.
// Returns length of string, not including nul, or -1 for error.
export fn fetchstr(address: c.uint64, buffer: [*c]u8, max: c_int) c_int {
    const process = c.myproc();
    const result = c.copyinstr(process.*.pagetable, buffer, address, @intCast(max));
    if (result < 0) {
        return -1;
    }
    return c.strlen(buffer);
}
