const elf = @import("elf.zig");
const mem = @import("memory.zig");
const ad = @import("address.zig");
const std = @import("std");

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

// Load a program segment into pagetable at virtual address va.
// va must be page-aligned
// and the pages from va to va+sz must already be mapped.
// Returns 0 on success, -1 on failure.
fn loadSegment(pageTable: ad.PageTablePtr, virtualAddress: ad.UserAddr, inode: *c.struct_inode, offset: u64, size: u64) !void {
    var currentPage: u32 = 0;
    while (currentPage < size) : (currentPage += ad.page_size) {
        const physicalAddress = mem.walkAddr(pageTable, virtualAddress.add(currentPage)) catch @panic("loadSegment: address should exist");

        // check if on last page
        const readCount = if (size - currentPage < ad.page_size) size - currentPage else ad.page_size;

        const readResult = c.readi(inode, 0, physicalAddress.toInt(), @intCast(offset + currentPage), @intCast(readCount));

        if (readResult != readCount) return error.CouldNotRead;
    }
}

pub fn exec(path: []const u8, argv: [][]const u8) !usize {
    if (argv.len > c.MAXARG) return error.TooManyArguments;

    const process = c.myproc();

    const pageTable = c.proc_pagetable(process) orelse return error.CouldNotGetProcessPgTable;
    var programSize: usize = 0;
    errdefer c.proc_freepagetable(pageTable, programSize);

    var inode: *c.struct_inode = undefined;
    var entry: usize = undefined;

    // load program into memory
    {
        c.begin_op();
        defer c.end_op();

        {
            //  TODO: remove
            var nullTermPath: [c.MAXPATH]u8 = undefined;
            @memcpy(&nullTermPath, path);
            nullTermPath[path.len] = 0;
            inode = c.namei(&nullTermPath) orelse return error.CouldResolvePath;
        }
        c.ilock(inode);
        defer c.iunlockput(inode);

        // Check ELF header
        var elfHeader: elf.ElfHeader = undefined;
        {
            const readBytes = c.readi(inode, 0, @intFromPtr(&elfHeader), 0, @sizeOf(elf.ElfHeader));
            if (readBytes != @sizeOf(elf.ElfHeader)) return error.CouldNotReadElfHeader;
            if (!elfHeader.elfIdentifier.isValid()) return error.CorruptedElfHeader;
        }
        entry = elfHeader.entry;

        // Load program into memory.
        var programHeader: elf.ProgramHeader = undefined;
        const programHeaderSize = @sizeOf(elf.ProgramHeader);
        for (0..elfHeader.programHeaderEntryNum) |programHeaderEntryIndex| {
            const offset = elfHeader.programHeaderOffset + programHeaderEntryIndex * programHeaderSize;
            const readBytes = c.readi(inode, 0, @intFromPtr(&programHeader), @intCast(offset), programHeaderSize);
            if (readBytes != programHeaderSize) return error.CouldNotReadProgramHeader;

            if (programHeader.type != .load) continue;
            if (programHeader.memorySize < programHeader.fileSize) return error.NotEnoughMemory;
            const newSize = @addWithOverflow(programHeader.virtualAddress, programHeader.memorySize);
            if (newSize[1] == 1) return error.MemoryAddressOverflow;

            const virtualAddress: ad.UserAddr = .fromInt(programHeader.virtualAddress);
            if (!virtualAddress.isPageAligned()) return error.MemoryNotPageAligned;

            const newProgramSize = try mem.uvmAlloc(@ptrCast(@alignCast(pageTable)), programSize, newSize[0], programHeader.flags.toPagePermissions());
            programSize = newProgramSize;

            try loadSegment(@ptrCast(@alignCast(pageTable)), virtualAddress, inode, programHeader.offset, programHeader.fileSize);
        }
    }

    const oldSize = process.*.sz;

    // Allocate two pages at the next page boundary.
    // Make the first inaccessible as a stack guard.
    // Use the second as the user stack.
    const alignedProgramSize = ad.pageRoundUp(programSize);
    programSize = try mem.uvmAlloc(@ptrCast(@alignCast(pageTable)), alignedProgramSize, alignedProgramSize + 2 * ad.page_size, .{ .read = true, .write = true });

    mem.uvmClearUser(@ptrCast(@alignCast(pageTable)), .fromInt(programSize - 2 * ad.page_size));
    var stackPointer = programSize;
    const stackBase = stackPointer - ad.page_size;

    var userStack: [c.MAXARG + 1]usize = undefined;

    // Push argument strings, prepare rest of stack in ustack.
    for (argv, 0..) |arg, index| {
        stackPointer -= arg.len + 1; // make room for terminator as well
        stackPointer -= stackPointer % 16; // riscv sp must be 16-byte aligned

        if (stackPointer < stackBase) return error.OutOfArgumentSpace;

        try mem.copyOutTerminated(@ptrCast(@alignCast(pageTable)), .fromInt(stackPointer), arg);
        userStack[index] = stackPointer;
    }
    userStack[argv.len] = 0;

    // push the array of argv[] pointers.
    stackPointer -= (argv.len + 1) * @sizeOf(usize); // make room for pointers and terminator
    stackPointer -= stackPointer % 16;
    if (stackPointer < stackBase) return error.OutOfArgumentPointerSpace;

    try mem.copyOut(@ptrCast(@alignCast(pageTable)), .fromInt(stackPointer), std.mem.sliceAsBytes(userStack[0..(argv.len + 1)]));

    // arguments to user main(argc, argv)
    // argc is returned via the system call return
    // value, which goes in a0.
    process.*.trapframe.*.a1 = stackPointer;

    // Save program name for debugging.
    var last: usize = 0; // index of first char of program name
    for (path, 0..) |char, index| {
        if (char == '/') { // finds word after last /
            last = index + 1;
        }
    }
    const name = path[last..];

    const len = @min(name.len, process.*.name.len - 1);
    @memcpy(process.*.name[0..len], name[0..len]);
    process.*.name[0][len] = 0;

    // Commit to the user image.
    const oldPageTable = process.*.pagetable;
    process.*.pagetable = pageTable;
    process.*.sz = programSize;
    process.*.trapframe.*.epc = entry; // initial program counter = main
    process.*.trapframe.*.sp = stackPointer;

    c.proc_freepagetable(oldPageTable, oldSize);

    return argv.len; // this ends up in a0, the first argument to main(argc, argv)
}
