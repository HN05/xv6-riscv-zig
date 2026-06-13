//
// the riscv Platform Level Interrupt Controller (PLIC).
//
const std = @import("std");
const ml = @import("memlayout.zig");

const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
});

// cast as ptr to a u32
inline fn castptr(addr: usize) *volatile u32 {
    return @ptrFromInt(addr);
}

fn getcpu() usize {
    return @intCast(c.cpuid());
}

pub fn init() void {
  // set desired IRQ priorities non-zero (otherwise disabled).
  castptr(ml.PLIC + ml.UART0_IRQ*4).* = 1;
  castptr(ml.PLIC + ml.VIRTIO0_IRQ*4).* = 1;
}

pub fn initHart() void {
    const hart = getcpu();

    // set enable bits for this hart's S-mode
    // for the uart and virtio disk.
    castptr(ml.PLIC_SENABLE(hart)).* = (1 << ml.UART0_IRQ) | (1 << ml.VIRTIO0_IRQ);
    // set this hart's S-mode priority threshold to 0.
    castptr(ml.PLIC_SPRIORITY(hart)).* = 0;
}

// ask the PLIC what interrupt we should serve.
pub fn claim() u32 {
    const hart = getcpu();
    const irq = castptr(ml.PLIC_SCLAIM(hart));
    return irq.*;
}

// tell the PLIC we've served this IRQ.
pub fn complete(irq: u32) void {
    const hart = getcpu();
    castptr(ml.PLIC_SCLAIM(hart)).* = irq;
}

