const std = @import("std");
const log = @import("klog.zig");
const sysargs = @import("sysargs.zig");
const ticks = @import("ticks.zig").ticks;

const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/proc.h");
    @cInclude("kernel/defs.h");
});

pub fn sys_exit() u64 {
    const exitCode = sysargs.int(.a0);
    c.exit(@intCast(exitCode));
    unreachable;
}

pub fn sys_getpid() u64 {
    return @intCast(c.myproc().*.pid);
}

pub fn sys_fork() u64 {
    return @intCast(c.fork());
}

pub fn sys_wait() u64 {
    const address = sysargs.int(.a0);
    return @intCast(c.wait(@intCast(address)));
}

pub fn sys_sbrk() u64 {
   const requestedBytes = sysargs.int(.a0);
    const oldSize = c.myproc().*.sz;

    if (c.growproc(@intCast(requestedBytes)) < 0) {
        return sysargs.errorVal;
    }
    return oldSize;
}

pub fn sys_sleep() u64 {
    const sleepTicks = sysargs.int(.a0);

    ticks.sleepFor(sleepTicks) catch {
        return sysargs.errorVal;
    };

    return 0;
}

pub fn sys_kill() u64 {
    return @intCast(c.kill(@intCast(sysargs.int(.a0))));
}

pub fn sys_uptime() u64 {
    return ticks.readSafe();
}

