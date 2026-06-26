//
// Console input and output, to the uart.
// Reads are line at a time.
// Implements special input characters:
//   newline -- end of line
//   control-h -- backspace
//   control-u -- kill line
//   control-d -- end of file
//   control-p -- print process list
//

const std = @import("std");
const SpinLock = @import("spinlock.zig").SpinLock;
const uart = @import("uart.zig");

const c = @cImport({
    @cInclude("kernel/types.h");
    @cInclude("kernel/param.h");
    @cInclude("kernel/spinlock.h");
    @cInclude("kernel/sleeplock.h");
    @cInclude("kernel/fs.h");
    @cInclude("kernel/file.h");
    @cInclude("kernel/memlayout.h");
    @cInclude("kernel/riscv.h");
    @cInclude("kernel/defs.h");
    @cInclude("kernel/proc.h");
});

fn control(char: u8) u8 {
    return char - '@';
}

const console_backspace = 0x100;
const backspace = '\x08';
const delete = '\x7f';
const input_buf_size = 128;

const InputBuffer = struct {
    lock: SpinLock = .{ .name = "console" },

    data: [input_buf_size]u8 = undefined,

    // Next buffered byte to return to consoleRead().
    // Advances as user read() consumes input.
    readIndex: usize = 0,

    // End of committed input.
    // Set to editIndex when Enter or Ctrl-D arrives; readers may consume up to this point.
    writeIndex: usize = 0,

    // End of the editable input line.
    // Advances as keyboard input arrives; moves backward on backspace/Ctrl-U.
    editIndex: usize = 0,
};

var inputBuffer: InputBuffer = .{};

pub fn init() void {
    uart.init();
    
    const consoleDevice = &c.devsw[c.CONSOLE];
    consoleDevice.read = &read;
    consoleDevice.write = &write;
}

//
// user write()s to the console go here.
//
fn write(user_src: c_int, src: c.uint64, n: c_int) callconv(.c) c_int {
    var i: c.uint64 = 0;

    while (i < n) : (i += 1) {
        var char: u8 = undefined;
        const res = c.either_copyin(&char, user_src, src + i, 1);

        if (res == -1) {
            break;
        }

        uart.putCharacter(char);
    }

    return @intCast(i);
}

//
// user read()s from the console go here.
// copy (up to) a whole input line to dst.
// user_dist indicates whether dst is a user
// or kernel address.
//
fn read(userDestination: c_int, start: c.uint64, n: c_int) callconv(.c) c_int {
    const target = n;
    var character: u8 = undefined;
    var characterBuffer: u8 = undefined;
    var destination = start;
    var charsLeft = n;

    inputBuffer.lock.acquire();
    defer inputBuffer.lock.release();

    while (charsLeft > 0) {
        // wait until interrupt handler has put some
        // input into cons.buffer.
        while (inputBuffer.readIndex == inputBuffer.writeIndex) {
            if (c.killed(c.myproc()) != 0) {
                return -1;
            }
            inputBuffer.lock.sleep(&inputBuffer.readIndex);
        }

        character = inputBuffer.data[inputBuffer.readIndex % input_buf_size];
        inputBuffer.readIndex += 1;

        if (character == control('D')) { // end of file
            if (charsLeft < target) {
                inputBuffer.readIndex -= 1;
                // Save ^D for next time, to make sure
                // caller gets a 0-byte result.
            }
            break;
        }
        // copy the input byte to the user-space buffer.
        characterBuffer = character;
        const result = c.either_copyout(userDestination, destination, &characterBuffer, 1);
        if (result == -1) {
            break;
        }

        destination += 1;
        charsLeft -= 1;

        if (character == '\n') {
            // a whole line has arrived, return to
            // the user-level read().
            break;
        }
    }

    return target - charsLeft;
}

//
// the console input interrupt handler.
// uartintr() calls this for input character.
// do erase/kill processing, append to cons.buf,
// wake up consoleread() if a whole line has arrived.
//
//

pub fn interrupt(character: u8) void {
    inputBuffer.lock.acquire();
    defer inputBuffer.lock.release();

    switch (character) {
        control('P') => { // print process list
            c.procdump();
        },
        control('U') => { // kill line
            while (inputBuffer.editIndex != inputBuffer.writeIndex) {
                // go until newline
                if (inputBuffer.data[(inputBuffer.editIndex - 1) % input_buf_size] == '\n') {
                    break;
                }
                inputBuffer.editIndex -= 1;
                putCharacter(console_backspace);
            }
        },
        delete, control('H') => {
            if (inputBuffer.editIndex == inputBuffer.writeIndex) {
                return;
            }
            inputBuffer.editIndex -= 1;
            putCharacter(console_backspace);
        },
        else => {
            if (character == 0) {
                return;
            }
            if ((inputBuffer.editIndex - inputBuffer.readIndex) >= input_buf_size) {
                return;
            }
            // make '\r' into '\n'
            const converted_character = if (character == '\r') '\n' else character;
            putCharacter(converted_character);

            // store for consumption by consoleread().
            inputBuffer.data[inputBuffer.editIndex % input_buf_size] = converted_character;
            inputBuffer.editIndex += 1;

            if (converted_character == '\n' or converted_character == control('D')) {
                // wake up consoleread() if a whole line (or end-of-file)
                // has arrived.
                inputBuffer.writeIndex = inputBuffer.editIndex;
                c.wakeup(&inputBuffer.readIndex);
            }
        },
    }
}

//
// send one character to the uart.
// called by printf(), and to echo input characters,
// but not from write().
//
pub fn putCharacter(char: u9) void {
    // if the user typed backspace, overwrite with a space.
    if (char == console_backspace) {
        uart.putCharSync(backspace);
        uart.putCharSync(' ');
        uart.putCharSync(backspace);
    } else {
        uart.putCharSync(@intCast(char));
    }
}

export fn consputc(char: c_int) void {
    putCharacter(@intCast(char));
}
