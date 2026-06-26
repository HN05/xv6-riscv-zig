const common = @import("common");
const param = common.param;
const registers = common.registers;
const csr = @import("csr.zig");
const p = @import("process.zig");

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

// Per-CPU state.
pub const Cpu = struct {
    runningProcess: ?*p.Process, // The process running on this cpu, or null.
    context: p.Context, // swtch() here to enter scheduler().
    pushDepth: usize, // Depth of push_off() nesting.
    interruptsEnabled: bool, // Were interrupts enabled before push_off()?

    // Must be called with interrupts disabled,
    // to prevent race with process being moved
    // to a different CPU.
    pub fn getCurrentId() usize {
        return registers.UserRegister.read(.tp);
    }

    pub fn getCurrent() *Cpu {
        return &cpuTable[getCurrentId()];
    }

    // push_off/pop_off are like intr_off()/intr_on() except that they are matched:
    // it takes two pop_off()s to undo two push_off()s.  Also, if interrupts
    // are initially off, then push_off, pop_off leaves them off.
    pub fn pushOff() void {
        const interruptsEnabled = csr.interruptsEnabled();
        csr.disableInterrupts();

        const cpu = getCurrent();
        if (cpu.pushDepth == 0) {
            cpu.interruptsEnabled = interruptsEnabled;
        }
        cpu.pushDepth += 1;
    }

    pub fn popOff() void {
        if (csr.interruptsEnabled()) {
            @panic("pop_off - interruptible");
        }

        const cpu = getCurrent();
        if (cpu.pushDepth < 1) {
            @panic("pop_off");
        }

        cpu.pushDepth -= 1;
        if (cpu.pushDepth == 0 and cpu.interruptsEnabled) {
            csr.enableInterrupts();
        }
    }
};

pub var cpuTable: [param.NCPU]Cpu = undefined;
