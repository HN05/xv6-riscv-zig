const std = @import("std");
const registers = @import("common").riscv.registers;

pub fn FlagOps(comptime Flag: type) type {
    return struct {
        pub fn mask(flag: Flag) usize {
            return @intFromEnum(flag);
        }

        pub fn set(flag: Flag, value: usize) usize {
            return value | mask(flag);
        }

        pub fn clear(flag: Flag, value: usize) usize {
            return value & ~mask(flag);
        }

        pub fn isSet(flag: Flag, value: usize) bool {
            return (value & mask(flag)) != 0;
        }
    };
}

pub fn CsrWithFlags(comptime name: []const u8, comptime Flag: type) type {
    return struct {
        pub const registerName = name;
        pub const flags = FlagOps(Flag);

        pub inline fn read() usize {
            return asm volatile ("csrr a0, " ++ name
                : [ret] "={a0}" (-> usize),
            );
        }

        pub inline fn write(value: usize) void {
            asm volatile ("csrw " ++ name ++ ", a0"
                :
                : [value] "{a0}" (value),
            );
        }

        pub fn set(bit: Flag) void {
            write(flags.set(bit, read()));
        }

        pub fn clear(bit: Flag) void {
            write(flags.clear(bit, read()));
        }

        pub fn isSet(bit: Flag) bool {
            return flags.isSet(bit, read());
        }
    };
}

pub fn Csr(comptime name: []const u8) type {
    return struct {
        pub const registerName = name;
        pub inline fn read() usize {
            return asm volatile ("csrr a0, " ++ name
                : [ret] "={a0}" (-> usize),
            );
        }

        pub inline fn write(value: usize) void {
            asm volatile ("csrw " ++ name ++ ", a0"
                :
                : [value] "{a0}" (value),
            );
        }
    };
}

pub fn CsrReadOnly(comptime name: []const u8) type {
    return struct {
        pub const registerName = name;
        pub inline fn read() usize {
            return asm volatile ("csrr a0, " ++ name
                : [ret] "={a0}" (-> usize),
            );
        }
    };
}

pub const Mhartid = CsrReadOnly("mhartid");

pub const Mepc = Csr("mepc");

pub const MstatusFlags = enum(usize) {
    Machine_interrupts_enable = 1 << 3,
};

pub const BaseMstatus = CsrWithFlags("mstatus", MstatusFlags);

pub const Mstatus = struct {
    pub const flags = BaseMstatus.flags;
    pub const Machine_prev_mask: usize = 3 << 11;
    pub const Mpp = enum(usize) {
        Machine = 3 << 11,
        Supervisor = 1 << 11,
        User = 0 << 11,
    };

    pub fn read() usize {
        return BaseMstatus.read();
    }

    pub fn write(value: usize) void {
        BaseMstatus.write(value);
    }

    pub fn set(flag: MstatusFlags) void {
        BaseMstatus.set(flag);
    }

    pub fn clear(flag: MstatusFlags) void {
        BaseMstatus.clear(flag);
    }

    pub fn isSet(flag: MstatusFlags) bool {
        return BaseMstatus.isSet(flag);
    }

    pub fn setMpp(mode: Mpp) void {
        const value = (read() & ~Machine_prev_mask) | @intFromEnum(mode);
        write(value);
    }
};

pub const SstatusFlags = enum(usize) {
    SPP = 1 << 8, // Previous mode, 1=Supervisor, 0=User
    SPIE = 1 << 5, // Supervisor Previous Interrupt Enable
    UPIE = 1 << 4, // User Previous Interrupt Enable
    SIE = 1 << 1, // Supervisor Interrupt Enable
    UIE = 1 << 0, // User Interrupt Enable
};

pub const Sstatus = CsrWithFlags("sstatus", SstatusFlags);

// enable device interrupts
pub fn interrupts_on() void {
    Sstatus.set(.SIE);
}

// disable device interrupts
pub fn interrupts_off() void {
    Sstatus.clear(.SIE);
}

// are device interrupts enabled?
pub fn interrupts_is_on() bool {
    return Sstatus.isSet(.SIE);
}

pub const SipFlags = enum(usize) {
    SSIP = 1 << 1, // supervisor software interrupt pending
    STIP = 1 << 5, // supervisor timer interrupt pending
    SEIP = 1 << 9, // supervisor external interrupt pending
};

pub const Sip = CsrWithFlags("sip", SipFlags);

// Supervisor Interrupt Enable
pub const SieFlags = enum(usize) {
    SEIE = 1 << 9, // external
    STIE = 1 << 5, // timer
    SSIE = 1 << 1, // software
};

pub const Sie = CsrWithFlags("sie", SieFlags);

// Machine-mode Interrupt Enable
pub const MieFlags = enum(usize) {
    MEIE = 1 << 11, // external
    MTIE = 1 << 7, // timer
    MSIE = 1 << 3, // software
};

pub const Mie = CsrWithFlags("mie", MieFlags);

// supervisor exception program counter, holds the
// instruction address to which a return from
// exception will go.
pub const Sepc = Csr("sepc");

// Machine Exception Delegation
pub const Medeleg = Csr("medeleg");

// Machine Interrupt Delegation
pub const Mideleg = Csr("mideleg");

// Supervisor Trap-Vector Base Address
// low two bits are mode.
pub const Stvec = Csr("stvec");

// Machine-mode interrupt vector
pub const Mtvec = Csr("mtvec");

// Physical Memory Protection
pub const Pmpcfg0 = Csr("pmpcfg0");

pub const Pmpaddr0 = Csr("pmpaddr0");

// supervisor address translation and protection;
// holds the address of the page table.
pub const Satp = Csr("satp");

pub const Mscratch = Csr("mscratch");

// Supervisor Trap Cause
pub const Scause = enum(usize) {
    const TrapKind = enum {
        syscall,
        interrupt,
        exception,
    };
    // Interrupt bit clear: synchronous exceptions
    instructionAddressMisaligned = 0,
    instructionAccessFault = 1,
    illegalInstruction = 2,
    breakpoint = 3,
    loadAddressMisaligned = 4,
    loadAccessFault = 5,
    storeAddressMisaligned = 6,
    storeAccessFault = 7,

    environmentCallFromUMode = 8,
    environmentCallFromSMode = 9,
    environmentCallFromVMode = 10,
    environmentCallFromMMode = 11,

    instructionPageFault = 12,
    loadPageFault = 13,
    storePageFault = 15,

    instructionGuestPageFault = 20,
    loadGuestPageFault = 21,
    virtualInstruction = 22,
    storeGuestPageFault = 23,

    softwareCheck = 24,
    hardwareError = 25,

    // Interrupt bit set
    userSoftwareInterrupt = interruptBit | 0,
    supervisorSoftwareInterrupt = interruptBit | 1,
    virtualSupervisorSoftwareInterrupt = interruptBit | 2,
    machineSoftwareInterrupt = interruptBit | 3,

    userTimerInterrupt = interruptBit | 4,
    supervisorTimerInterrupt = interruptBit | 5,
    virtualSupervisorTimerInterrupt = interruptBit | 6,
    machineTimerInterrupt = interruptBit | 7,

    userExternalInterrupt = interruptBit | 8,
    supervisorExternalInterrupt = interruptBit | 9,
    virtualSupervisorExternalInterrupt = interruptBit | 10,
    machineExternalInterrupt = interruptBit | 11,

    supervisorGuestExternalInterrupt = interruptBit | 12,
    localCounterOverflowInterrupt = interruptBit | 13,

    // Allows storing platform/custom/unknown scause values too.
    _,

    const interruptBit: usize = 1 << (@bitSizeOf(usize) - 1);

    pub fn raw(self: Scause) usize {
        return @intFromEnum(self);
    }

    pub fn isInterrupt(self: Scause) bool {
        return (self.raw() & interruptBit) != 0;
    }

    pub fn code(self: Scause) usize {
        return self.raw() & ~interruptBit;
    }

    pub fn kind(self: Scause) TrapKind {
        return switch (self) {
            .environmentCallFromUMode => .syscall,

            .userSoftwareInterrupt,
            .supervisorSoftwareInterrupt,
            .virtualSupervisorSoftwareInterrupt,
            .machineSoftwareInterrupt,
            .userTimerInterrupt,
            .supervisorTimerInterrupt,
            .virtualSupervisorTimerInterrupt,
            .machineTimerInterrupt,
            .userExternalInterrupt,
            .supervisorExternalInterrupt,
            .virtualSupervisorExternalInterrupt,
            .machineExternalInterrupt,
            .supervisorGuestExternalInterrupt,
            .localCounterOverflowInterrupt,
            => .interrupt,

            else => .exception,
        };
    }

    pub inline fn readRaw() usize {
        return asm volatile ("csrr a0, scause"
            : [ret] "={a0}" (-> usize),
        );
    }

    pub fn read() Scause {
        return @enumFromInt(readRaw());
    }
};

// Supervisor Trap Value
pub const Stval = CsrReadOnly("stval");

// Machine-mode Counter-Enable
pub const Mcounteren = Csr("mcounteren");

// machine-mode cycle counter
pub const Time = CsrReadOnly("time");
