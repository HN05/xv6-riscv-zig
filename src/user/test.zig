const mixin = @import("./ulib/mixin.zig");
const param = @import("common").param;
const sys = @import("./ulib/user.zig");

pub const c_main = mixin.ProgMixin.c_main;
comptime {
    @export(&c_main, .{ .name = "main", .linkage = .strong });
    @export(&c_main, .{ .name = "_start", .linkage = .strong });
}

// root overrides for std lib
pub const std_options = mixin.std_options;
pub const os = mixin.os;

// Keep these synced with kernel/fcntl.h.
const O_RDONLY: i32 = 0x000;
const O_WRONLY: i32 = 0x001;
const O_RDWR: i32 = 0x002;
const O_CREATE: i32 = 0x200;
const O_TRUNC: i32 = 0x400;

const BSIZE = 1024;
const PGSIZE = 4096;
const BUFSZ = (param.max_num_operation_blocks + 2) * BSIZE;
const MAXFILE = 12 + BSIZE / @sizeOf(u32);

// Your custom directory ABI.
const ZIG_DIRSIZ = 27;

var buf: [BUFSZ]u8 = undefined;
var uninit: [10000]u8 = [_]u8{0} ** 10000;
var big_arg_ptr: *anyopaque = @ptrFromInt(0xeaeb0b5b00002f5e);

const TestFn = *const fn ([*:0]const u8) void;

const Test = struct {
    f: ?TestFn,
    name: ?[*:0]const u8,
};

const ZigDirent = extern struct {
    inum: u32 = 0,
    name_length: u8 = 0,
    name: [ZIG_DIRSIZ]u8 = [_]u8{0} ** ZIG_DIRSIZ,
};

fn printf(comptime fmt: [*:0]const u8, args: anytype) void {
    sys.printf(fmt, args);
}

fn fail(comptime fmt: [*:0]const u8, args: anytype) noreturn {
    sys.printf(fmt, args);
    sys.exit(1);
}

fn streqZ(a: [*:0]const u8, b: [*:0]const u8) bool {
    var i: usize = 0;
    while (a[i] != 0 and b[i] != 0) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == b[i];
}

fn strlenZ(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

fn appendBytes(dst: []u8, pos: *usize, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[pos.*] = src[i];
        pos.* += 1;
    }
    dst[pos.*] = 0;
}

fn path2(a: []const u8, b: []const u8) [128:0]u8 {
    var out: [128:0]u8 = [_:0]u8{0} ** 128;
    var pos: usize = 0;
    appendBytes(out[0..], &pos, a);
    appendBytes(out[0..], &pos, "/");
    appendBytes(out[0..], &pos, b);
    return out;
}

fn path3(a: []const u8, b: []const u8, c: []const u8) [128:0]u8 {
    var out: [128:0]u8 = [_:0]u8{0} ** 128;
    var pos: usize = 0;
    appendBytes(out[0..], &pos, a);
    appendBytes(out[0..], &pos, "/");
    appendBytes(out[0..], &pos, b);
    appendBytes(out[0..], &pos, "/");
    appendBytes(out[0..], &pos, c);
    return out;
}

fn rawWrite(fd: sys.FileDescriptor, ptr_int: usize, len: usize) isize {
    @setRuntimeSafety(false);
    const p: [*]const u8 = @ptrFromInt(ptr_int);
    return if (sys.write(fd, p[0..len])) |n| @intCast(n) else |_| -1;
}

fn rawRead(fd: sys.FileDescriptor, ptr_int: usize, len: usize) isize {
    @setRuntimeSafety(false);
    const p: [*]u8 = @ptrFromInt(ptr_int);
    return if (sys.read(fd, p[0..len])) |n| @intCast(n) else |_| -1;
}

fn rawOpen(path_ptr_int: usize, flags: i32) i32 {
    @setRuntimeSafety(false);
    const p: [*c]const u8 = @ptrFromInt(path_ptr_int);
    return sys.open(p, flags) catch -1;
}

fn rawUnlink(path_ptr_int: usize) i32 {
    @setRuntimeSafety(false);
    const p: [*c]const u8 = @ptrFromInt(path_ptr_int);
    sys.unlink(p) catch return -1;
    return 0;
}

fn rawLink(old_ptr_int: usize, new_ptr_int: usize) i32 {
    @setRuntimeSafety(false);
    const oldp: [*c]const u8 = @ptrFromInt(old_ptr_int);
    const newp: [*c]const u8 = @ptrFromInt(new_ptr_int);
    sys.link(oldp, newp) catch return -1;
    return 0;
}

fn rawExec(path_ptr_int: usize, argv: [*c][*c]u8) i32 {
    @setRuntimeSafety(false);
    const path: [*c]const u8 = @ptrFromInt(path_ptr_int);
    sys.exec(path, argv) catch return -1;
    unreachable;
}

fn maybeUnlink(path: [*c]const u8) void {
    sys.unlink(path) catch {};
}

fn closeIgnore(fd: sys.FileDescriptor) void {
    if (fd >= 0) sys.close(fd) catch {};
}

fn writeAllOrFail(fd: sys.FileDescriptor, data: []const u8, s: [*:0]const u8) void {
    const n = sys.write(fd, data) catch {
        fail("%s: write failed\n", .{s});
    };
    if (n != data.len) fail("%s: write failed\n", .{s});
}

fn readOrFail(fd: sys.FileDescriptor, dst: []u8, s: [*:0]const u8) usize {
    return sys.read(fd, dst) catch {
        fail("%s: read failed\n", .{s});
    };
}

fn setName2(name: *[3:0]u8, a: u8, b: u8) void {
    name[0] = a;
    name[1] = b;
    name[2] = 0;
}

fn memsetBytes(dst: []u8, value: u8) void {
    for (dst) |*b| b.* = value;
}

// what if you pass ridiculous pointers to system calls that read user memory with copyin?
fn copyin(_: [*:0]const u8) void {
    const addrs = [_]usize{ 0x80000000, 0xffffffffffffffff };

    for (addrs) |addr| {
        const fd = sys.open("copyin1", O_CREATE | O_WRONLY) catch {
            fail("open(copyin1) failed\n", .{});
        };

        const n = rawWrite(fd, addr, 8192);
        if (n >= 0) fail("write(fd, %x, 8192) returned %d, not -1\n", .{ @as(u64, @intCast(addr)), @as(i32, @intCast(n)) });

        closeIgnore(fd);
        maybeUnlink("copyin1");

        const n2 = rawWrite(1, addr, 8192);
        if (n2 > 0) fail("write(1, %x, 8192) returned %d, not -1 or 0\n", .{ @as(u64, @intCast(addr)), @as(i32, @intCast(n2)) });

        var fds: [2]sys.FileDescriptor = undefined;
        sys.pipe(&fds) catch fail("pipe() failed\n", .{});

        const n3 = rawWrite(fds[1], addr, 8192);
        if (n3 > 0) fail("write(pipe, %x, 8192) returned %d, not -1 or 0\n", .{ @as(u64, @intCast(addr)), @as(i32, @intCast(n3)) });

        closeIgnore(fds[0]);
        closeIgnore(fds[1]);
    }
}

// what if you pass ridiculous pointers to system calls that write user memory with copyout?
fn copyout(_: [*:0]const u8) void {
    const addrs = [_]usize{ 0x80000000, 0xffffffffffffffff };

    for (addrs) |addr| {
        const fd = sys.open("README.md", O_RDONLY) catch {
            fail("open(README.md) failed\n", .{});
        };

        const n = rawRead(fd, addr, 8192);
        if (n > 0) fail("read(fd, %x, 8192) returned %d, not -1 or 0\n", .{ @as(u64, @intCast(addr)), @as(i32, @intCast(n)) });

        closeIgnore(fd);

        var fds: [2]sys.FileDescriptor = undefined;
        sys.pipe(&fds) catch fail("pipe() failed\n", .{});

        _ = sys.write(fds[1], "x") catch fail("pipe write failed\n", .{});

        const n2 = rawRead(fds[0], addr, 8192);
        if (n2 > 0) fail("read(pipe, %x, 8192) returned %d, not -1 or 0\n", .{ @as(u64, @intCast(addr)), @as(i32, @intCast(n2)) });

        closeIgnore(fds[0]);
        closeIgnore(fds[1]);
    }
}

// what if you pass ridiculous string pointers to system calls?
fn copyinstr1(_: [*:0]const u8) void {
    const addrs = [_]usize{ 0x80000000, 0xffffffffffffffff };

    for (addrs) |addr| {
        const fd = rawOpen(addr, O_CREATE | O_WRONLY);
        if (fd >= 0) fail("open(%x) returned %d, not -1\n", .{ @as(u64, @intCast(addr)), fd });
    }
}

// what if a string system call argument is exactly the size of the kernel buffer it is copied into.
fn copyinstr2(_: [*:0]const u8) void {
    var b: [param.MAXPATH + 1:0]u8 = [_:0]u8{0} ** (param.MAXPATH + 1);

    var i: usize = 0;
    while (i < param.MAXPATH) : (i += 1) b[i] = 'x';
    b[param.MAXPATH] = 0;

    if (sys.unlink(&b)) {
        fail("unlink(%s) returned 0, not -1\n", .{&b});
    } else |_| {}

    if (sys.open(&b, O_CREATE | O_WRONLY)) |fd| {
        fail("open(%s) returned %d, not -1\n", .{ &b, fd });
    } else |_| {}

    if (sys.link(&b, &b)) {
        fail("link(%s, %s) returned 0, not -1\n", .{ &b, &b });
    } else |_| {}

    const arg0: [*c]u8 = @constCast("xx");
    var args = [_:null]?[*c]u8{ arg0, null };
    const ret = rawExec(@intFromPtr(&b), @ptrCast(&args));
    if (ret != -1) fail("exec(%s) returned %d, not -1\n", .{ &b, ret });

    const pid = sys.fork() catch fail("fork failed\n", .{});
    if (pid == null) {
        var big: [PGSIZE + 1:0]u8 = [_:0]u8{0} ** (PGSIZE + 1);
        i = 0;
        while (i < PGSIZE) : (i += 1) big[i] = 'x';
        big[PGSIZE] = 0;

        var args2 = [_:null]?[*c]u8{
            @ptrCast(&big),
            @ptrCast(&big),
            @ptrCast(&big),
            null,
        };

        const r = rawExec(@intFromPtr("echo"), @ptrCast(&args2));
        if (r != -1) fail("exec(echo, BIG) returned %d, not -1\n", .{r});
        sys.exit(747);
    }

    var st: i32 = 0;
    _ = sys.wait(&st);
    if (st != 747) fail("exec(echo, BIG) succeeded, should have failed\n", .{});
}

// what if a string argument crosses over the end of last user page?
fn copyinstr3(_: [*:0]const u8) void {
    _ = sys.sbrk(8192);

    var top: usize = @intFromPtr(sys.sbrk(0));
    if ((top % PGSIZE) != 0) _ = sys.sbrk(@intCast(PGSIZE - (top % PGSIZE)));

    top = @intFromPtr(sys.sbrk(0));
    if ((top % PGSIZE) != 0) fail("oops\n", .{});

    @setRuntimeSafety(false);
    const b: [*]u8 = @ptrFromInt(top - 1);
    b[0] = 'x';
    const bp = top - 1;

    const ret1 = rawUnlink(bp);
    if (ret1 != -1) fail("unlink(cross-page) returned %d, not -1\n", .{ret1});

    const fd = rawOpen(bp, O_CREATE | O_WRONLY);
    if (fd != -1) fail("open(cross-page) returned %d, not -1\n", .{fd});

    const ret2 = rawLink(bp, bp);
    if (ret2 != -1) fail("link(cross-page, cross-page) returned %d, not -1\n", .{ret2});

    const arg0: [*c]u8 = @constCast("xx");
    var args = [_:null]?[*c]u8{ arg0, null };
    const ret3 = rawExec(bp, @ptrCast(&args));
    if (ret3 != -1) fail("exec(cross-page) returned %d, not -1\n", .{ret3});
}

// See if the kernel refuses to read/write user memory that the application doesn't have anymore.
fn rwsbrk(_: [*:0]const u8) void {
    const a = @intFromPtr(sys.sbrk(8192));

    if (a == 0xffffffffffffffff) fail("sbrk(rwsbrk) failed\n", .{});
    if (@intFromPtr(sys.sbrk(-8192)) == 0xffffffffffffffff) fail("sbrk(rwsbrk) shrink failed\n", .{});

    var fd = sys.open("rwsbrk", O_CREATE | O_WRONLY) catch fail("open(rwsbrk) failed\n", .{});
    var n = rawWrite(fd, a + 4096, 1024);
    if (n >= 0) fail("write(fd, %x, 1024) returned %d, not -1\n", .{ @as(u64, @intCast(a + 4096)), @as(i32, @intCast(n)) });

    closeIgnore(fd);
    maybeUnlink("rwsbrk");

    fd = sys.open("README.md", O_RDONLY) catch fail("open(rwsbrk) failed\n", .{});
    n = rawRead(fd, a + 4096, 10);
    if (n >= 0) fail("read(fd, %x, 10) returned %d, not -1\n", .{ @as(u64, @intCast(a + 4096)), @as(i32, @intCast(n)) });

    closeIgnore(fd);
    sys.exit(0);
}

// test O_TRUNC.
fn truncate1(s: [*:0]const u8) void {
    var local_buf: [32]u8 = undefined;

    maybeUnlink("truncfile");
    var fd1 = sys.open("truncfile", O_CREATE | O_WRONLY | O_TRUNC) catch fail("%s: open truncfile failed\n", .{s});
    writeAllOrFail(fd1, "abcd", s);
    closeIgnore(fd1);

    const fd2 = sys.open("truncfile", O_RDONLY) catch fail("%s: open truncfile read failed\n", .{s});
    var n = readOrFail(fd2, local_buf[0..], s);
    if (n != 4) fail("%s: read %d bytes, wanted 4\n", .{ s, @as(i32, @intCast(n)) });

    fd1 = sys.open("truncfile", O_WRONLY | O_TRUNC) catch fail("%s: open truncfile truncate failed\n", .{s});

    const fd3 = sys.open("truncfile", O_RDONLY) catch fail("%s: open truncfile fd3 failed\n", .{s});
    n = readOrFail(fd3, local_buf[0..], s);
    if (n != 0) {
        printf("aaa fd3=%d\n", .{fd3});
        fail("%s: read %d bytes, wanted 0\n", .{ s, @as(i32, @intCast(n)) });
    }

    n = readOrFail(fd2, local_buf[0..], s);
    if (n != 0) {
        printf("bbb fd2=%d\n", .{fd2});
        fail("%s: read %d bytes, wanted 0\n", .{ s, @as(i32, @intCast(n)) });
    }

    writeAllOrFail(fd1, "abcdef", s);

    n = readOrFail(fd3, local_buf[0..], s);
    if (n != 6) fail("%s: read %d bytes, wanted 6\n", .{ s, @as(i32, @intCast(n)) });

    n = readOrFail(fd2, local_buf[0..], s);
    if (n != 2) fail("%s: read %d bytes, wanted 2\n", .{ s, @as(i32, @intCast(n)) });

    maybeUnlink("truncfile");
    closeIgnore(fd1);
    closeIgnore(fd2);
    closeIgnore(fd3);
}

// write to an open FD whose file has just been truncated.
fn truncate2(s: [*:0]const u8) void {
    maybeUnlink("truncfile");

    const fd1 = sys.open("truncfile", O_CREATE | O_TRUNC | O_WRONLY) catch fail("%s: open truncfile failed\n", .{s});
    writeAllOrFail(fd1, "abcd", s);

    const fd2 = sys.open("truncfile", O_TRUNC | O_WRONLY) catch fail("%s: truncate reopen failed\n", .{s});

    const n = sys.write(fd1, "x") catch 0xffff_ffff;
    if (n != 0xffff_ffff) fail("%s: write returned %d, expected -1\n", .{ s, @as(i32, @intCast(n)) });

    maybeUnlink("truncfile");
    closeIgnore(fd1);
    closeIgnore(fd2);
}

fn truncate3(s: [*:0]const u8) void {
    closeIgnore(sys.open("truncfile", O_CREATE | O_TRUNC | O_WRONLY) catch -1);

    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid == null) {
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            var local_buf: [32]u8 = undefined;

            const fd = sys.open("truncfile", O_WRONLY) catch fail("%s: open failed\n", .{s});
            const n = sys.write(fd, "1234567890") catch 0;
            if (n != 10) fail("%s: write got %d, expected 10\n", .{ s, @as(i32, @intCast(n)) });
            closeIgnore(fd);

            const fd2 = sys.open("truncfile", O_RDONLY) catch fail("%s: open read failed\n", .{s});
            _ = sys.read(fd2, local_buf[0..]) catch 0;
            closeIgnore(fd2);
        }
        sys.exit(0);
    }

    var i: usize = 0;
    while (i < 150) : (i += 1) {
        const fd = sys.open("truncfile", O_CREATE | O_WRONLY | O_TRUNC) catch fail("%s: open failed\n", .{s});
        const n = sys.write(fd, "xxx") catch 0;
        if (n != 3) fail("%s: write got %d, expected 3\n", .{ s, @as(i32, @intCast(n)) });
        closeIgnore(fd);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    maybeUnlink("truncfile");
    sys.exit(xstatus);
}

// does chdir() call iput(p->cwd) in a transaction?
fn iputtest(s: [*:0]const u8) void {
    sys.mkdir("iputdir") catch fail("%s: mkdir failed\n", .{s});
    sys.chdir("iputdir") catch fail("%s: chdir iputdir failed\n", .{s});
    sys.unlink("../iputdir") catch fail("%s: unlink ../iputdir failed\n", .{s});
    sys.chdir("/") catch fail("%s: chdir / failed\n", .{s});
}

// does exit() call iput(p->cwd) in a transaction?
fn exitiputtest(s: [*:0]const u8) void {
    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid == null) {
        sys.mkdir("iputdir") catch fail("%s: mkdir failed\n", .{s});
        sys.chdir("iputdir") catch fail("%s: child chdir failed\n", .{s});
        sys.unlink("../iputdir") catch fail("%s: unlink ../iputdir failed\n", .{s});
        sys.exit(0);
    }
    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    sys.exit(xstatus);
}

fn openiputtest(s: [*:0]const u8) void {
    sys.mkdir("oidir") catch fail("%s: mkdir oidir failed\n", .{s});
    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});

    if (pid == null) {
        if (sys.open("oidir", O_RDWR)) |fd| {
            _ = fd;
            fail("%s: open directory for write succeeded\n", .{s});
        } else |_| {}
        sys.exit(0);
    }

    sys.sleep(1) catch {};
    sys.unlink("oidir") catch fail("%s: unlink failed\n", .{s});
    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    sys.exit(xstatus);
}

fn opentest(s: [*:0]const u8) void {
    const fd = sys.open("echo", O_RDONLY) catch fail("%s: open echo failed!\n", .{s});
    closeIgnore(fd);

    if (sys.open("doesnotexist", O_RDONLY)) |fd2| {
        _ = fd2;
        fail("%s: open doesnotexist succeeded!\n", .{s});
    } else |_| {}
}

fn writetest(s: [*:0]const u8) void {
    const N = 100;
    const SZ = 10;

    const fd = sys.open("small", O_CREATE | O_RDWR) catch fail("%s: error: creat small failed!\n", .{s});

    var i: usize = 0;
    while (i < N) : (i += 1) {
        if ((sys.write(fd, "aaaaaaaaaa") catch 0) != SZ) fail("%s: error: write aa %d new file failed\n", .{ s, @as(i32, @intCast(i)) });
        if ((sys.write(fd, "bbbbbbbbbb") catch 0) != SZ) fail("%s: error: write bb %d new file failed\n", .{ s, @as(i32, @intCast(i)) });
    }
    closeIgnore(fd);

    const fd2 = sys.open("small", O_RDONLY) catch fail("%s: error: open small failed!\n", .{s});
    const n = sys.read(fd2, buf[0 .. N * SZ * 2]) catch 0;
    if (n != N * SZ * 2) fail("%s: read failed\n", .{s});
    closeIgnore(fd2);

    sys.unlink("small") catch fail("%s: unlink small failed\n", .{s});
}

fn writebig(s: [*:0]const u8) void {
    const fd = sys.open("big", O_CREATE | O_RDWR) catch fail("%s: error: creat big failed!\n", .{s});

    var i: usize = 0;
    while (i < MAXFILE) : (i += 1) {
        const ip: *u32 = @ptrCast(@alignCast(&buf[0]));
        ip.* = @intCast(i);
        if ((sys.write(fd, buf[0..BSIZE]) catch 0) != BSIZE) fail("%s: error: write big file failed %d\n", .{ s, @as(i32, @intCast(i)) });
    }

    closeIgnore(fd);

    const fd2 = sys.open("big", O_RDONLY) catch fail("%s: error: open big failed!\n", .{s});

    var nblocks: usize = 0;
    while (true) {
        const n = sys.read(fd2, buf[0..BSIZE]) catch fail("%s: read failed\n", .{s});
        if (n == 0) {
            if (nblocks == MAXFILE - 1) fail("%s: read only %d blocks from big\n", .{ s, @as(i32, @intCast(nblocks)) });
            break;
        } else if (n != BSIZE) {
            fail("%s: read failed %d\n", .{ s, @as(i32, @intCast(n)) });
        }

        const ip: *u32 = @ptrCast(@alignCast(&buf[0]));
        if (ip.* != nblocks) fail("%s: read content of block %d is %d\n", .{ s, @as(i32, @intCast(nblocks)), @as(i32, @intCast(ip.*)) });
        nblocks += 1;
    }

    closeIgnore(fd2);
    sys.unlink("big") catch fail("%s: unlink big failed\n", .{s});
}

fn createtest(_: [*:0]const u8) void {
    const N = 52;
    var name: [3:0]u8 = .{ 'a', 0, 0 };

    var i: i32 = 0;
    while (i < N) : (i += 1) {
        name[1] = @intCast('0' + i);
        const fd = sys.open(&name, O_CREATE | O_RDWR) catch -1;
        closeIgnore(fd);
    }

    i = 0;
    while (i < N) : (i += 1) {
        name[1] = @intCast('0' + i);
        maybeUnlink(&name);
    }
}

fn dirtest(s: [*:0]const u8) void {
    sys.mkdir("dir0") catch fail("%s: mkdir failed\n", .{s});
    sys.chdir("dir0") catch fail("%s: chdir dir0 failed\n", .{s});
    sys.chdir("..") catch fail("%s: chdir .. failed\n", .{s});
    sys.unlink("dir0") catch fail("%s: unlink dir0 failed\n", .{s});
}

fn exectest(s: [*:0]const u8) void {
    maybeUnlink("echo-ok");

    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid == null) {
        closeIgnore(1);
        const fd = sys.open("echo-ok", O_CREATE | O_WRONLY) catch fail("%s: create failed\n", .{s});
        if (fd != 1) fail("%s: wrong fd\n", .{s});

        var argv = [_:null]?[*c]u8{ @constCast("echo"), @constCast("OK"), null };
        sys.exec("echo", @ptrCast(&argv)) catch fail("%s: exec echo failed\n", .{s});
        unreachable;
    }

    var xstatus: i32 = 0;
    if (sys.wait(&xstatus) != pid.?) fail("%s: wait failed!\n", .{s});
    if (xstatus != 0) sys.exit(xstatus);

    const fd = sys.open("echo-ok", O_RDONLY) catch fail("%s: open failed\n", .{s});
    var out: [3]u8 = undefined;
    if ((sys.read(fd, out[0..2]) catch 0) != 2) fail("%s: read failed\n", .{s});
    maybeUnlink("echo-ok");
    if (out[0] == 'O' and out[1] == 'K') sys.exit(0);
    fail("%s: wrong output\n", .{s});
}

fn pipe1(s: [*:0]const u8) void {
    const N = 5;
    const SZ = 1033;

    var fds: [2]sys.FileDescriptor = undefined;
    sys.pipe(&fds) catch fail("%s: pipe() failed\n", .{s});

    const pid = sys.fork() catch fail("%s: fork() failed\n", .{s});
    var seq: i32 = 0;

    if (pid == null) {
        closeIgnore(fds[0]);
        var n: usize = 0;
        while (n < N) : (n += 1) {
            var i: usize = 0;
            while (i < SZ) : (i += 1) {
                buf[i] = @intCast(seq & 0xff);
                seq += 1;
            }
            if ((sys.write(fds[1], buf[0..SZ]) catch 0) != SZ) fail("%s: pipe1 oops 1\n", .{s});
        }
        sys.exit(0);
    }

    closeIgnore(fds[1]);
    var total: usize = 0;
    var cc: usize = 1;
    while (true) {
        const n = sys.read(fds[0], buf[0..cc]) catch 0;
        if (n == 0) break;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            if ((buf[i] & 0xff) != @as(u8, @intCast(seq & 0xff))) {
                printf("%s: pipe1 oops 2\n", .{s});
                return;
            }
            seq += 1;
        }

        total += n;
        cc *= 2;
        if (cc > buf.len) cc = buf.len;
    }

    if (total != N * SZ) fail("%s: pipe1 oops 3 total %d\n", .{ s, @as(i32, @intCast(total)) });
    closeIgnore(fds[0]);

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    sys.exit(xstatus);
}

fn killstatus(s: [*:0]const u8) void {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid == null) {
            while (true) _ = sys.getpid() catch 0;
        }
        sys.sleep(1) catch {};
        sys.kill(pid.?) catch {};
        var xst: i32 = 0;
        _ = sys.wait(&xst);
        if (xst != -1) fail("%s: status should be -1\n", .{s});
    }
    sys.exit(0);
}

fn preempt(s: [*:0]const u8) void {
    const pid1 = sys.fork() catch fail("%s: fork failed", .{s});
    if (pid1 == null) while (true) {};

    const pid2 = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid2 == null) while (true) {};

    var pfds: [2]sys.FileDescriptor = undefined;
    sys.pipe(&pfds) catch {};

    const pid3 = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid3 == null) {
        closeIgnore(pfds[0]);
        if ((sys.write(pfds[1], "x") catch 0) != 1) printf("%s: preempt write error", .{s});
        closeIgnore(pfds[1]);
        while (true) {}
    }

    closeIgnore(pfds[1]);
    if ((sys.read(pfds[0], buf[0..]) catch 0) != 1) {
        printf("%s: preempt read error", .{s});
        return;
    }
    closeIgnore(pfds[0]);

    printf("kill... ", .{});
    sys.kill(pid1.?) catch {};
    sys.kill(pid2.?) catch {};
    sys.kill(pid3.?) catch {};
    printf("wait... ", .{});
    var st: i32 = 0;
    _ = sys.wait(&st);
    _ = sys.wait(&st);
    _ = sys.wait(&st);
}

fn exitwait(s: [*:0]const u8) void {
    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid) |child_pid| {
            var xstate: i32 = 0;
            if (sys.wait(&xstate) != child_pid) fail("%s: wait wrong pid\n", .{s});
            if (i != xstate) fail("%s: wait wrong exit status\n", .{s});
        } else {
            sys.exit(i);
        }
    }
}

fn reparent(s: [*:0]const u8) void {
    const master_pid = sys.getpid() catch 0;

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid) |child_pid| {
            var st: i32 = 0;
            if (sys.wait(&st) != child_pid) fail("%s: wait wrong pid\n", .{s});
        } else {
            const pid2 = sys.fork() catch {
                sys.kill(master_pid) catch {};
                sys.exit(1);
            };
            _ = pid2;
            sys.exit(0);
        }
    }
    sys.exit(0);
}

fn twochildren(s: [*:0]const u8) void {
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const pid1 = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid1 == null) sys.exit(0);

        const pid2 = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid2 == null) sys.exit(0);

        var st: i32 = 0;
        _ = sys.wait(&st);
        _ = sys.wait(&st);
    }
}

fn forkfork(s: [*:0]const u8) void {
    const N = 2;

    var i: usize = 0;
    while (i < N) : (i += 1) {
        const pid = sys.fork() catch fail("%s: fork failed", .{s});
        if (pid == null) {
            var j: usize = 0;
            while (j < 200) : (j += 1) {
                const pid1 = sys.fork() catch sys.exit(1);
                if (pid1 == null) sys.exit(0);
                var st: i32 = 0;
                _ = sys.wait(&st);
            }
            sys.exit(0);
        }
    }

    i = 0;
    while (i < N) : (i += 1) {
        var xstatus: i32 = 0;
        _ = sys.wait(&xstatus);
        if (xstatus != 0) fail("%s: fork in child failed", .{s});
    }
}

fn forkforkfork(s: [*:0]const u8) void {
    maybeUnlink("stopforking");

    const pid = sys.fork() catch fail("%s: fork failed", .{s});
    if (pid == null) {
        while (true) {
            if (sys.open("stopforking", O_RDONLY)) |fd| {
                closeIgnore(fd);
                sys.exit(0);
            } else |_| {}

            if (sys.fork()) |maybe_pid| {
                if (maybe_pid == null) sys.exit(0);
            } else |_| {
                closeIgnore(sys.open("stopforking", O_CREATE | O_RDWR) catch -1);
            }
        }
    }

    sys.sleep(20) catch {};
    closeIgnore(sys.open("stopforking", O_CREATE | O_RDWR) catch -1);
    var st: i32 = 0;
    _ = sys.wait(&st);
    sys.sleep(10) catch {};
}

fn reparent2(_: [*:0]const u8) void {
    var i: usize = 0;
    while (i < 800) : (i += 1) {
        const pid1 = sys.fork() catch fail("fork failed\n", .{});
        if (pid1 == null) {
            _ = sys.fork() catch null;
            _ = sys.fork() catch null;
            sys.exit(0);
        }
        var st: i32 = 0;
        _ = sys.wait(&st);
    }
    sys.exit(0);
}

// allocate all mem, free it, and allocate again.
// This Zig port keeps the same fork/exit behavior but avoids libc malloc/free dependency.
fn mem(_: [*:0]const u8) void {
    const pid = sys.fork() catch fail("fork failed\n", .{});
    if (pid == null) {
        var pages: i32 = 0;
        while (pages < 128) : (pages += 1) {
            const p = sys.sbrk(PGSIZE);
            if (@intFromPtr(p) == 0xffffffffffffffff) break;
            @setRuntimeSafety(false);
            p[0] = 1;
        }
        _ = sys.sbrk(-pages * PGSIZE);
        const p2 = sys.sbrk(1024 * 20);
        if (@intFromPtr(p2) == 0xffffffffffffffff) fail("couldn't allocate mem?!!\n", .{});
        _ = sys.sbrk(-(1024 * 20));
        sys.exit(0);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus == -1) sys.exit(0);
    sys.exit(xstatus);
}

fn sharedfd(s: [*:0]const u8) void {
    const N = 1000;
    const SZ = 10;

    maybeUnlink("sharedfd");
    const fd = sys.open("sharedfd", O_CREATE | O_RDWR) catch fail("%s: cannot open sharedfd for writing", .{s});

    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});

    var local: [SZ]u8 = undefined;
    memsetBytes(local[0..], if (pid == null) 'c' else 'p');

    var i: usize = 0;
    while (i < N) : (i += 1) {
        if ((sys.write(fd, local[0..]) catch 0) != SZ) fail("%s: write sharedfd failed\n", .{s});
    }

    if (pid == null) sys.exit(0);

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus != 0) sys.exit(xstatus);

    closeIgnore(fd);

    const fd2 = sys.open("sharedfd", O_RDONLY) catch fail("%s: cannot open sharedfd for reading\n", .{s});
    var nc: usize = 0;
    var np: usize = 0;

    while (true) {
        const n = sys.read(fd2, local[0..]) catch 0;
        if (n == 0) break;
        i = 0;
        while (i < n) : (i += 1) {
            if (local[i] == 'c') nc += 1;
            if (local[i] == 'p') np += 1;
        }
    }

    closeIgnore(fd2);
    maybeUnlink("sharedfd");

    if (nc == N * SZ and np == N * SZ) sys.exit(0);
    fail("%s: nc/np test fails\n", .{s});
}

fn fourfiles(s: [*:0]const u8) void {
    const N = 12;
    const NCHILD = 4;
    const SZ = 500;

    const names = [_][*:0]const u8{ "f0", "f1", "f2", "f3" };

    var pi: usize = 0;
    while (pi < NCHILD) : (pi += 1) {
        const fname = names[pi];
        maybeUnlink(fname);

        const pid = sys.fork() catch fail("fork failed\n", .{});
        if (pid == null) {
            const fd = sys.open(fname, O_CREATE | O_RDWR) catch fail("create failed\n", .{});
            memsetBytes(buf[0..SZ], @intCast('0' + pi));

            var i: usize = 0;
            while (i < N) : (i += 1) {
                const n = sys.write(fd, buf[0..SZ]) catch 0;
                if (n != SZ) fail("write failed %d\n", .{@as(i32, @intCast(n))});
            }
            sys.exit(0);
        }
    }

    pi = 0;
    while (pi < NCHILD) : (pi += 1) {
        var xstatus: i32 = 0;
        _ = sys.wait(&xstatus);
        if (xstatus != 0) sys.exit(xstatus);
    }

    var i: usize = 0;
    while (i < NCHILD) : (i += 1) {
        const fname = names[i];
        const fd = sys.open(fname, O_RDONLY) catch fail("%s: open failed\n", .{s});
        var total: usize = 0;

        while (true) {
            const n = sys.read(fd, buf[0..]) catch 0;
            if (n == 0) break;

            var j: usize = 0;
            while (j < n) : (j += 1) {
                if (buf[j] != @as(u8, @intCast('0' + i))) fail("wrong char\n", .{});
            }
            total += n;
        }

        closeIgnore(fd);
        if (total != N * SZ) fail("wrong length %d\n", .{@as(i32, @intCast(total))});
        maybeUnlink(fname);
    }
}

fn createdelete(s: [*:0]const u8) void {
    const N = 20;
    const NCHILD = 4;
    var name: [32:0]u8 = [_:0]u8{0} ** 32;

    var pi: usize = 0;
    while (pi < NCHILD) : (pi += 1) {
        const pid = sys.fork() catch fail("fork failed\n", .{});
        if (pid == null) {
            name[0] = @intCast('p' + pi);
            name[2] = 0;

            var i: usize = 0;
            while (i < N) : (i += 1) {
                name[1] = @intCast('0' + i);
                const fd = sys.open(&name, O_CREATE | O_RDWR) catch fail("%s: create failed\n", .{s});
                closeIgnore(fd);

                if (i > 0 and (i % 2) == 0) {
                    name[1] = @intCast('0' + (i / 2));
                    sys.unlink(&name) catch fail("%s: unlink failed\n", .{s});
                }
            }
            sys.exit(0);
        }
    }

    pi = 0;
    while (pi < NCHILD) : (pi += 1) {
        var xstatus: i32 = 0;
        _ = sys.wait(&xstatus);
        if (xstatus != 0) sys.exit(1);
    }

    var i: usize = 0;
    while (i < N) : (i += 1) {
        pi = 0;
        while (pi < NCHILD) : (pi += 1) {
            name[0] = @intCast('p' + pi);
            name[1] = @intCast('0' + i);
            name[2] = 0;

            const fd_or_err = sys.open(&name, O_RDONLY);
            if ((i == 0 or i >= N / 2) and fd_or_err catch -1 < 0) {
                fail("%s: oops createdelete %s didn't exist\n", .{ s, &name });
            } else if ((i >= 1 and i < N / 2)) {
                if (fd_or_err) |fd| {
                    closeIgnore(fd);
                    fail("%s: oops createdelete %s did exist\n", .{ s, &name });
                } else |_| {}
            }
            if (fd_or_err) |fd| closeIgnore(fd) else |_| {}
        }
    }

    i = 0;
    while (i < N) : (i += 1) {
        pi = 0;
        while (pi < NCHILD) : (pi += 1) {
            name[0] = @intCast('p' + i);
            name[1] = @intCast('0' + i);
            name[2] = 0;
            maybeUnlink(&name);
        }
    }
}

fn unlinkread(s: [*:0]const u8) void {
    const SZ = 5;

    var fd = sys.open("unlinkread", O_CREATE | O_RDWR) catch fail("%s: create unlinkread failed\n", .{s});
    writeAllOrFail(fd, "hello", s);
    closeIgnore(fd);

    fd = sys.open("unlinkread", O_RDWR) catch fail("%s: open unlinkread failed\n", .{s});
    sys.unlink("unlinkread") catch fail("%s: unlink unlinkread failed\n", .{s});

    const fd1 = sys.open("unlinkread", O_CREATE | O_RDWR) catch -1;
    writeAllOrFail(fd1, "yyy", s);
    closeIgnore(fd1);

    if ((sys.read(fd, buf[0..]) catch 0) != SZ) fail("%s: unlinkread read failed", .{s});
    if (buf[0] != 'h') fail("%s: unlinkread wrong data\n", .{s});
    if ((sys.write(fd, buf[0..10]) catch 0) != 10) fail("%s: unlinkread write failed\n", .{s});
    closeIgnore(fd);
    maybeUnlink("unlinkread");
}

fn linktest(s: [*:0]const u8) void {
    const SZ = 5;

    maybeUnlink("lf1");
    maybeUnlink("lf2");

    var fd = sys.open("lf1", O_CREATE | O_RDWR) catch fail("%s: create lf1 failed\n", .{s});
    if ((sys.write(fd, "hello") catch 0) != SZ) fail("%s: write lf1 failed\n", .{s});
    closeIgnore(fd);

    sys.link("lf1", "lf2") catch fail("%s: link lf1 lf2 failed\n", .{s});
    maybeUnlink("lf1");

    if (sys.open("lf1", O_RDONLY)) |fdx| {
        _ = fdx;
        fail("%s: unlinked lf1 but it is still there!\n", .{s});
    } else |_| {}

    fd = sys.open("lf2", O_RDONLY) catch fail("%s: open lf2 failed\n", .{s});
    if ((sys.read(fd, buf[0..]) catch 0) != SZ) fail("%s: read lf2 failed\n", .{s});
    closeIgnore(fd);

    if (sys.link("lf2", "lf2")) {
        fail("%s: link lf2 lf2 succeeded! oops\n", .{s});
    } else |_| {}

    maybeUnlink("lf2");

    if (sys.link("lf2", "lf1")) {
        fail("%s: link non-existent succeeded! oops\n", .{s});
    } else |_| {}

    if (sys.link(".", "lf1")) {
        fail("%s: link . lf1 succeeded! oops\n", .{s});
    } else |_| {}
}

fn concreate(s: [*:0]const u8) void {
    const N = 40;

    var file: [3:0]u8 = .{ 'C', 0, 0 };
    var fa: [N]u8 = [_]u8{0} ** N;

    var i: i32 = 0;
    while (i < N) : (i += 1) {
        file[1] = @intCast('0' + i);
        maybeUnlink(&file);

        const pid = sys.fork() catch fail("fork failed\n", .{});
        if (pid != null and @mod(i, 3) == 1) {
            sys.link("C0", &file) catch {};
        } else if (pid == null and @mod(i, 5) == 1) {
            sys.link("C0", &file) catch {};
        } else {
            const fd = sys.open(&file, O_CREATE | O_RDWR) catch fail("concreate create %s failed\n", .{&file});
            closeIgnore(fd);
        }

        if (pid == null) sys.exit(0);

        var xstatus: i32 = 0;
        _ = sys.wait(&xstatus);
        if (xstatus != 0) sys.exit(1);
    }

    memsetBytes(fa[0..], 0);
    const fd = sys.open(".", O_RDONLY) catch fail("%s: open . failed\n", .{s});
    var n: usize = 0;
    var de: ZigDirent = undefined;

    while ((sys.read(fd, @as([*]u8, @ptrCast(&de))[0..@sizeOf(ZigDirent)]) catch 0) == @sizeOf(ZigDirent)) {
        if (de.inum == 0) continue;

        if (de.name_length == 2 and de.name[0] == 'C') {
            const idx: i32 = @as(i32, de.name[1]) - '0';
            if (idx < 0 or idx >= fa.len) {
                printf("%s: concreate weird file ", .{s});
                var j: usize = 0;
                while (j < de.name_length and j < ZIG_DIRSIZ) : (j += 1) printf("%c", .{de.name[j]});
                printf("\n", .{});
                sys.exit(1);
            }

            const uidx: usize = @intCast(idx);
            if (fa[uidx] != 0) {
                printf("%s: concreate duplicate file ", .{s});
                var j: usize = 0;
                while (j < de.name_length and j < ZIG_DIRSIZ) : (j += 1) printf("%c", .{de.name[j]});
                printf("\n", .{});
                sys.exit(1);
            }

            fa[uidx] = 1;
            n += 1;
        }
    }

    closeIgnore(fd);

    if (n != N) fail("%s: concreate not enough files in directory listing\n", .{s});

    i = 0;
    while (i < N) : (i += 1) {
        file[1] = @intCast('0' + i);
        const pid = sys.fork() catch fail("%s: fork failed\n", .{s});

        if ((@mod(i, 3) == 0 and pid == null) or (@mod(i, 3) == 1 and pid != null)) {
            var k: usize = 0;
            while (k < 6) : (k += 1) closeIgnore(sys.open(&file, O_RDONLY) catch -1);
        } else {
            var k: usize = 0;
            while (k < 6) : (k += 1) maybeUnlink(&file);
        }

        if (pid == null) sys.exit(0);
        var st: i32 = 0;
        _ = sys.wait(&st);
    }
}

fn linkunlink(s: [*:0]const u8) void {
    maybeUnlink("x");

    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
    var x: u32 = if (pid != null) 1 else 97;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        x = x *% 1103515245 +% 12345;

        if ((x % 3) == 0) {
            closeIgnore(sys.open("x", O_RDWR | O_CREATE) catch -1);
        } else if ((x % 3) == 1) {
            sys.link("cat", "x") catch {};
        } else {
            maybeUnlink("x");
        }
    }

    if (pid != null) {
        var st: i32 = 0;
        _ = sys.wait(&st);
    } else {
        sys.exit(0);
    }
}

fn subdir(s: [*:0]const u8) void {
    maybeUnlink("ff");
    sys.mkdir("dd") catch fail("%s: mkdir dd failed\n", .{s});

    var fd = sys.open("dd/ff", O_CREATE | O_RDWR) catch fail("%s: create dd/ff failed\n", .{s});
    writeAllOrFail(fd, "ff", s);
    closeIgnore(fd);

    if (sys.unlink("dd")) {
        fail("%s: unlink dd (non-empty dir) succeeded!\n", .{s});
    } else |_| {}

    sys.mkdir("/dd/dd") catch fail("subdir mkdir dd/dd failed\n", .{});

    fd = sys.open("dd/dd/ff", O_CREATE | O_RDWR) catch fail("%s: create dd/dd/ff failed\n", .{s});
    writeAllOrFail(fd, "FF", s);
    closeIgnore(fd);

    fd = sys.open("dd/dd/../ff", O_RDONLY) catch fail("%s: open dd/dd/../ff failed\n", .{s});
    const cc = sys.read(fd, buf[0..]) catch 0;
    if (cc != 2 or buf[0] != 'f') fail("%s: dd/dd/../ff wrong content\n", .{s});
    closeIgnore(fd);

    sys.link("dd/dd/ff", "dd/dd/ffff") catch fail("link dd/dd/ff dd/dd/ffff failed\n", .{});
    sys.unlink("dd/dd/ff") catch fail("%s: unlink dd/dd/ff failed\n", .{s});

    if (sys.open("dd/dd/ff", O_RDONLY)) |fdx| {
        _ = fdx;
        fail("%s: open (unlinked) dd/dd/ff succeeded\n", .{s});
    } else |_| {}

    sys.chdir("dd") catch fail("%s: chdir dd failed\n", .{s});
    sys.chdir("dd/../../dd") catch fail("%s: chdir dd/../../dd failed\n", .{s});
    sys.chdir("dd/../../../dd") catch fail("chdir dd/../../dd failed\n", .{});
    sys.chdir("./..") catch fail("%s: chdir ./.. failed\n", .{s});

    fd = sys.open("dd/dd/ffff", O_RDONLY) catch fail("%s: open dd/dd/ffff failed\n", .{s});
    if ((sys.read(fd, buf[0..]) catch 0) != 2) fail("%s: read dd/dd/ffff wrong len\n", .{s});
    closeIgnore(fd);

    if (sys.open("dd/dd/ff", O_RDONLY)) |fdx| {
        _ = fdx;
        fail("%s: open (unlinked) dd/dd/ff succeeded!\n", .{s});
    } else |_| {}

    if (sys.open("dd/ff/ff", O_CREATE | O_RDWR)) |fdx| {
        _ = fdx;
        fail("%s: create dd/ff/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.open("dd/xx/ff", O_CREATE | O_RDWR)) |fdx| {
        _ = fdx;
        fail("%s: create dd/xx/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.open("dd", O_CREATE)) |fdx| {
        _ = fdx;
        fail("%s: create dd succeeded!\n", .{s});
    } else |_| {}
    if (sys.open("dd", O_RDWR)) |fdx| {
        _ = fdx;
        fail("%s: open dd rdwr succeeded!\n", .{s});
    } else |_| {}
    if (sys.open("dd", O_WRONLY)) |fdx| {
        _ = fdx;
        fail("%s: open dd wronly succeeded!\n", .{s});
    } else |_| {}

    if (sys.link("dd/ff/ff", "dd/dd/xx")) {
        fail("%s: link dd/ff/ff dd/dd/xx succeeded!\n", .{s});
    } else |_| {}
    if (sys.link("dd/xx/ff", "dd/dd/xx")) {
        fail("%s: link dd/xx/ff dd/dd/xx succeeded!\n", .{s});
    } else |_| {}
    if (sys.link("dd/ff", "dd/dd/ffff")) {
        fail("%s: link dd/ff dd/dd/ffff succeeded!\n", .{s});
    } else |_| {}
    if (sys.mkdir("dd/ff/ff")) {
        fail("%s: mkdir dd/ff/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.mkdir("dd/xx/ff")) {
        fail("%s: mkdir dd/xx/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.mkdir("dd/dd/ffff")) {
        fail("%s: mkdir dd/dd/ffff succeeded!\n", .{s});
    } else |_| {}
    if (sys.unlink("dd/xx/ff")) {
        fail("%s: unlink dd/xx/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.unlink("dd/ff/ff")) {
        fail("%s: unlink dd/ff/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.chdir("dd/ff")) {
        fail("%s: chdir dd/ff succeeded!\n", .{s});
    } else |_| {}
    if (sys.chdir("dd/xx")) {
        fail("%s: chdir dd/xx succeeded!\n", .{s});
    } else |_| {}

    sys.unlink("dd/dd/ffff") catch fail("%s: unlink dd/dd/ff failed\n", .{s});
    sys.unlink("dd/ff") catch fail("%s: unlink dd/ff failed\n", .{s});
    if (sys.unlink("dd")) {
        fail("%s: unlink non-empty dd succeeded!\n", .{s});
    } else |_| {}
    sys.unlink("dd/dd") catch fail("%s: unlink dd/dd failed\n", .{s});
    sys.unlink("dd") catch fail("%s: unlink dd failed\n", .{s});
}

fn bigwrite(s: [*:0]const u8) void {
    maybeUnlink("bigwrite");

    var sz: usize = 499;
    while (sz < (param.max_num_operation_blocks + 2) * BSIZE) : (sz += 471) {
        const fd = sys.open("bigwrite", O_CREATE | O_RDWR) catch fail("%s: cannot create bigwrite\n", .{s});
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            const cc = sys.write(fd, buf[0..sz]) catch 0;
            if (cc != sz) fail("%s: write(%d) ret %d\n", .{ s, @as(i32, @intCast(sz)), @as(i32, @intCast(cc)) });
        }
        closeIgnore(fd);
        maybeUnlink("bigwrite");
    }
}

fn bigfile(s: [*:0]const u8) void {
    const N = 20;
    const SZ = 600;

    maybeUnlink("bigfile.dat");
    var fd = sys.open("bigfile.dat", O_CREATE | O_RDWR) catch fail("%s: cannot create bigfile", .{s});

    var i: usize = 0;
    while (i < N) : (i += 1) {
        memsetBytes(buf[0..SZ], @intCast(i));
        if ((sys.write(fd, buf[0..SZ]) catch 0) != SZ) fail("%s: write bigfile failed\n", .{s});
    }
    closeIgnore(fd);

    fd = sys.open("bigfile.dat", O_RDONLY) catch fail("%s: cannot open bigfile\n", .{s});
    var total: usize = 0;
    i = 0;
    while (true) : (i += 1) {
        const cc = sys.read(fd, buf[0 .. SZ / 2]) catch fail("%s: read bigfile failed\n", .{s});
        if (cc == 0) break;
        if (cc != SZ / 2) fail("%s: short read bigfile\n", .{s});
        if (buf[0] != @as(u8, @intCast(i / 2)) or buf[SZ / 2 - 1] != @as(u8, @intCast(i / 2))) {
            fail("%s: read bigfile wrong data\n", .{s});
        }
        total += cc;
    }
    closeIgnore(fd);
    if (total != N * SZ) fail("%s: read bigfile wrong total\n", .{s});
    maybeUnlink("bigfile.dat");
}

fn fourteen(s: [*:0]const u8) void {
    const name27 = "123456789012345678901234567";
    const name28 = "1234567890123456789012345678";

    sys.mkdir(name27) catch fail("%s: mkdir 27-char name failed\n", .{s});

    if (sys.mkdir(name28)) {
        fail("%s: mkdir 28-char name succeeded!\n", .{s});
    } else |_| {}

    var p2 = path2(name27, name27);
    sys.mkdir(&p2) catch fail("%s: mkdir 27/27 failed\n", .{s});

    var p3 = path3(name27, name27, name27);
    var fd = sys.open(&p3, O_CREATE) catch fail("%s: create 27/27/27 failed\n", .{s});
    closeIgnore(fd);

    fd = sys.open(&p3, O_RDONLY) catch fail("%s: open 27/27/27 failed\n", .{s});
    closeIgnore(fd);

    if (sys.mkdir(&p3)) {
        fail("%s: mkdir existing 27/27/27 succeeded!\n", .{s});
    } else |_| {}

    maybeUnlink(&p3);
    maybeUnlink(&p2);
    maybeUnlink(name27);
}

fn rmdot(s: [*:0]const u8) void {
    sys.mkdir("dots") catch fail("%s: mkdir dots failed\n", .{s});
    sys.chdir("dots") catch fail("%s: chdir dots failed\n", .{s});

    if (sys.unlink(".")) {
        fail("%s: rm . worked!\n", .{s});
    } else |_| {}
    if (sys.unlink("..")) {
        fail("%s: rm .. worked!\n", .{s});
    } else |_| {}

    sys.chdir("/") catch fail("%s: chdir / failed\n", .{s});

    if (sys.unlink("dots/.")) {
        fail("%s: unlink dots/. worked!\n", .{s});
    } else |_| {}
    if (sys.unlink("dots/..")) {
        fail("%s: unlink dots/.. worked!\n", .{s});
    } else |_| {}

    sys.unlink("dots") catch fail("%s: unlink dots failed!\n", .{s});
}

fn dirfile(s: [*:0]const u8) void {
    var fd = sys.open("dirfile", O_CREATE) catch fail("%s: create dirfile failed\n", .{s});
    closeIgnore(fd);

    if (sys.chdir("dirfile")) {
        fail("%s: chdir dirfile succeeded!\n", .{s});
    } else |_| {}
    if (sys.open("dirfile/xx", O_RDONLY)) |fdx| {
        _ = fdx;
        fail("%s: create dirfile/xx succeeded!\n", .{s});
    } else |_| {}
    if (sys.open("dirfile/xx", O_CREATE)) |fdx| {
        _ = fdx;
        fail("%s: create dirfile/xx succeeded!\n", .{s});
    } else |_| {}
    if (sys.mkdir("dirfile/xx")) {
        fail("%s: mkdir dirfile/xx succeeded!\n", .{s});
    } else |_| {}
    if (sys.unlink("dirfile/xx")) {
        fail("%s: unlink dirfile/xx succeeded!\n", .{s});
    } else |_| {}
    if (sys.link("README.md", "dirfile/xx")) {
        fail("%s: link to dirfile/xx succeeded!\n", .{s});
    } else |_| {}

    sys.unlink("dirfile") catch fail("%s: unlink dirfile failed!\n", .{s});

    if (sys.open(".", O_RDWR)) |fdx| {
        _ = fdx;
        fail("%s: open . for writing succeeded!\n", .{s});
    } else |_| {}

    fd = sys.open(".", O_RDONLY) catch fail("%s: open . failed\n", .{s});
    if ((sys.write(fd, "x") catch 0) > 0) fail("%s: write . succeeded!\n", .{s});
    closeIgnore(fd);
}

fn iref(s: [*:0]const u8) void {
    var i: usize = 0;
    while (i < param.NINODE + 1) : (i += 1) {
        sys.mkdir("irefd") catch fail("%s: mkdir irefd failed\n", .{s});
        sys.chdir("irefd") catch fail("%s: chdir irefd failed\n", .{s});

        sys.mkdir("") catch {};
        sys.link("README.md", "") catch {};
        if (sys.open("", O_CREATE)) |fd| closeIgnore(fd) else |_| {}
        if (sys.open("xx", O_CREATE)) |fd| closeIgnore(fd) else |_| {}
        maybeUnlink("xx");
    }

    i = 0;
    while (i < param.NINODE + 1) : (i += 1) {
        sys.chdir("..") catch {};
        maybeUnlink("irefd");
    }

    sys.chdir("/") catch {};
}

fn forktest(s: [*:0]const u8) void {
    const N = 1000;
    var n: usize = 0;

    while (n < N) : (n += 1) {
        const pid = sys.fork() catch break;
        if (pid == null) sys.exit(0);
    }

    if (n == 0) fail("%s: no fork at all!\n", .{s});
    if (n == N) fail("%s: fork claimed to work 1000 times!\n", .{s});

    while (n > 0) : (n -= 1) {
        var st: i32 = 0;
        if (sys.wait(&st) < 0) fail("%s: wait stopped early\n", .{s});
    }

    var st: i32 = 0;
    if (sys.wait(&st) != -1) fail("%s: wait got too many\n", .{s});
}

fn sbrkbasic(s: [*:0]const u8) void {
    const TOOMUCH = 1024 * 1024 * 1024;

    const pid = sys.fork() catch fail("fork failed in sbrkbasic\n", .{});
    if (pid == null) {
        const a = sys.sbrk(TOOMUCH);
        if (@intFromPtr(a) == 0xffffffffffffffff) sys.exit(0);

        var p: usize = @intFromPtr(a);
        while (p < @intFromPtr(a) + TOOMUCH) : (p += PGSIZE) {
            @setRuntimeSafety(false);
            const q: [*]u8 = @ptrFromInt(p);
            q[0] = 99;
        }
        sys.exit(1);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus == 1) fail("%s: too much memory allocated!\n", .{s});

    var a = sys.sbrk(0);
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        const b = sys.sbrk(1);
        if (@intFromPtr(b) != @intFromPtr(a)) fail("%s: sbrk test failed %d %x %x\n", .{ s, @as(i32, @intCast(i)), @as(u64, @intFromPtr(a)), @as(u64, @intFromPtr(b)) });
        @setRuntimeSafety(false);
        b[0] = 1;
        a = @ptrFromInt(@intFromPtr(b) + 1);
    }

    const pid2 = sys.fork() catch fail("%s: sbrk test fork failed\n", .{s});
    const c1 = sys.sbrk(1);
    const c2 = sys.sbrk(1);
    _ = c1;
    if (@intFromPtr(c2) != @intFromPtr(a) + 1) fail("%s: sbrk test failed post-fork\n", .{s});
    if (pid2 == null) sys.exit(0);
    _ = sys.wait(&xstatus);
    sys.exit(xstatus);
}

fn sbrkmuch(s: [*:0]const u8) void {
    const BIG = 100 * 1024 * 1024;

    const oldbrk = sys.sbrk(0);
    const a = sys.sbrk(0);
    const amt: i32 = @intCast(BIG - @intFromPtr(a));
    const p = sys.sbrk(amt);
    if (@intFromPtr(p) != @intFromPtr(a)) fail("%s: sbrk test failed to grow big address space; enough phys mem?\n", .{s});

    const eee = sys.sbrk(0);
    var pp = @intFromPtr(a);
    while (pp < @intFromPtr(eee)) : (pp += PGSIZE) {
        @setRuntimeSafety(false);
        const q: [*]u8 = @ptrFromInt(pp);
        q[0] = 1;
    }

    @setRuntimeSafety(false);
    const lastaddr: [*]u8 = @ptrFromInt(BIG - 1);
    lastaddr[0] = 99;

    const a2 = sys.sbrk(0);
    const c = sys.sbrk(-PGSIZE);
    if (@intFromPtr(c) == 0xffffffffffffffff) fail("%s: sbrk could not deallocate\n", .{s});
    const c2 = sys.sbrk(0);
    if (@intFromPtr(c2) != @intFromPtr(a2) - PGSIZE) fail("%s: sbrk deallocation produced wrong address\n", .{s});

    const a3 = sys.sbrk(0);
    const c3 = sys.sbrk(PGSIZE);
    if (@intFromPtr(c3) != @intFromPtr(a3) or @intFromPtr(sys.sbrk(0)) != @intFromPtr(a3) + PGSIZE) {
        fail("%s: sbrk re-allocation failed\n", .{s});
    }
    if (lastaddr[0] == 99) fail("%s: sbrk de-allocation didn't really deallocate\n", .{s});

    const a4 = sys.sbrk(0);
    const down = @intFromPtr(sys.sbrk(0)) - @intFromPtr(oldbrk);
    const c4 = sys.sbrk(-@as(i32, @intCast(down)));
    if (@intFromPtr(c4) != @intFromPtr(a4)) fail("%s: sbrk downsize failed\n", .{s});
}

fn kernmem(s: [*:0]const u8) void {
    var a: usize = 0x80000000;
    while (a < 0x80000000 + 2000000) : (a += 50000) {
        const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid == null) {
            @setRuntimeSafety(false);
            const p: [*]u8 = @ptrFromInt(a);
            printf("%s: oops could read %x = %x\n", .{ s, @as(u64, @intCast(a)), @as(u64, p[0]) });
            sys.exit(1);
        }
        var xstatus: i32 = 0;
        _ = sys.wait(&xstatus);
        if (xstatus != -1) sys.exit(1);
    }
}

fn MAXVAplus(s: [*:0]const u8) void {
    var a: usize = 1 << (9 + 9 + 9 + 12 - 1);
    while (a != 0) : (a <<= 1) {
        const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
        if (pid == null) {
            @setRuntimeSafety(false);
            const p: [*]u8 = @ptrFromInt(a);
            p[0] = 99;
            printf("%s: oops wrote %x\n", .{ s, @as(u64, @intCast(a)) });
            sys.exit(1);
        }
        var xstatus: i32 = 0;
        _ = sys.wait(&xstatus);
        if (xstatus != -1) sys.exit(1);
    }
}

fn sbrkfail(s: [*:0]const u8) void {
    const BIG = 100 * 1024 * 1024;
    var fds: [2]sys.FileDescriptor = undefined;
    sys.pipe(&fds) catch fail("%s: pipe() failed\n", .{s});

    var pids: [10]sys.Pid = [_]sys.Pid{-1} ** 10;
    var scratch: [1]u8 = undefined;

    var i: usize = 0;
    while (i < pids.len) : (i += 1) {
        const pid = sys.fork() catch null;
        if (pid == null) {
            _ = sys.sbrk(@intCast(BIG - @intFromPtr(sys.sbrk(0))));
            _ = sys.write(fds[1], "x") catch 0;
            while (true) sys.sleep(1000) catch {};
        } else if (pid) |child| {
            pids[i] = child;
            _ = sys.read(fds[0], scratch[0..]) catch 0;
        }
    }

    const c = sys.sbrk(PGSIZE);
    i = 0;
    while (i < pids.len) : (i += 1) {
        if (pids[i] == -1) continue;
        sys.kill(pids[i]) catch {};
        var st: i32 = 0;
        _ = sys.wait(&st);
    }

    if (@intFromPtr(c) == 0xffffffffffffffff) fail("%s: failed sbrk leaked memory\n", .{s});

    const pid2 = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid2 == null) {
        const a = sys.sbrk(0);
        _ = sys.sbrk(10 * BIG);
        var n: i32 = 0;
        i = 0;
        while (i < 10 * BIG) : (i += PGSIZE) {
            @setRuntimeSafety(false);
            const p: [*]u8 = @ptrFromInt(@intFromPtr(a) + i);
            n += p[0];
        }
        printf("%s: allocate a lot of memory succeeded %d\n", .{ s, n });
        sys.exit(1);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus != -1 and xstatus != 2) sys.exit(1);
}

fn sbrkarg(s: [*:0]const u8) void {
    var a = sys.sbrk(PGSIZE);
    const fd = sys.open("sbrk", O_CREATE | O_WRONLY) catch fail("%s: open sbrk failed\n", .{s});
    maybeUnlink("sbrk");

    const ptr: [*]u8 = @ptrCast(a);
    const n = sys.write(fd, ptr[0..PGSIZE]) catch fail("%s: write sbrk failed\n", .{s});
    _ = n;
    closeIgnore(fd);

    a = sys.sbrk(PGSIZE);
    const fds_ptr: *[2]sys.FileDescriptor = @ptrCast(@alignCast(a));
    sys.pipe(fds_ptr) catch fail("%s: pipe() failed\n", .{s});
}

fn validatetest(s: [*:0]const u8) void {
    const hi: usize = 1100 * 1024;
    var p: usize = 0;
    while (p <= hi) : (p += PGSIZE) {
        @setRuntimeSafety(false);
        const path: [*c]const u8 = @ptrFromInt(p);
        if (sys.link("nosuchfile", path)) {
            fail("%s: link should not succeed\n", .{s});
        } else |_| {}
    }
}

fn bsstest(s: [*:0]const u8) void {
    for (uninit) |v| {
        if (v != 0) fail("%s: bss test failed\n", .{s});
    }
}

fn bigargtest(s: [*:0]const u8) void {
    maybeUnlink("bigarg-ok");

    const pid = sys.fork() catch fail("%s: bigargtest: fork failed\n", .{s});
    if (pid == null) {
        var args: [param.MAXARG:null]?[*c]u8 = [_:null]?[*c]u8{null} ** param.MAXARG;
        var i: usize = 0;
        while (i < param.MAXARG - 1) : (i += 1) {
            args[i] = @constCast("bigargs test: failed\n                                                                                                                                                                                                       ");
        }
        args[param.MAXARG - 1] = null;
        sys.exec("echo", @ptrCast(&args)) catch {};
        closeIgnore(sys.open("bigarg-ok", O_CREATE) catch -1);
        sys.exit(0);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus != 0) sys.exit(xstatus);

    const fd = sys.open("bigarg-ok", O_RDONLY) catch fail("%s: bigarg test failed!\n", .{s});
    closeIgnore(fd);
}

fn fsfull() void {
    var nfiles: i32 = 0;
    const fsblocks: i32 = 0;
    _ = fsblocks;

    printf("fsfull test\n", .{});

    while (true) : (nfiles += 1) {
        var name: [64:0]u8 = [_:0]u8{0} ** 64;
        name[0] = 'f';
        name[1] = @intCast('0' + @divTrunc(nfiles, 1000));
        name[2] = @intCast('0' + @divTrunc(@mod(nfiles, 1000), 100));
        name[3] = @intCast('0' + @divTrunc(@mod(nfiles, 100), 10));
        name[4] = @intCast('0' + @mod(nfiles, 10));
        name[5] = 0;

        printf("writing %s\n", .{&name});
        const fd = sys.open(&name, O_CREATE | O_RDWR) catch {
            printf("open %s failed\n", .{&name});
            break;
        };

        var total: usize = 0;
        while (true) {
            const cc = sys.write(fd, buf[0..BSIZE]) catch 0;
            if (cc < BSIZE) break;
            total += cc;
        }
        printf("wrote %d bytes\n", .{@as(i32, @intCast(total))});
        closeIgnore(fd);
        if (total == 0) break;
    }

    while (nfiles >= 0) : (nfiles -= 1) {
        var name: [64:0]u8 = [_:0]u8{0} ** 64;
        name[0] = 'f';
        name[1] = @intCast('0' + @divTrunc(nfiles, 1000));
        name[2] = @intCast('0' + @divTrunc(@mod(nfiles, 1000), 100));
        name[3] = @intCast('0' + @divTrunc(@mod(nfiles, 100), 10));
        name[4] = @intCast('0' + @mod(nfiles, 10));
        name[5] = 0;
        maybeUnlink(&name);
    }

    printf("fsfull test finished\n", .{});
}

fn argptest(_: [*:0]const u8) void {
    const fd = sys.open("init", O_RDONLY) catch fail("argptest: open failed\n", .{});
    const end = @intFromPtr(sys.sbrk(0)) - 1;
    _ = rawRead(fd, end, 0xffffffffffffffff);
    closeIgnore(fd);
}

fn stacktest(s: [*:0]const u8) void {
    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid == null) {
        var sp: usize = 0;
        asm volatile ("mv %[ret], sp"
            : [ret] "=r" (sp),
        );
        sp -= PGSIZE;
        @setRuntimeSafety(false);
        const p: [*]u8 = @ptrFromInt(sp);
        printf("%s: stacktest: read below stack %x\n", .{ s, @as(u64, p[0]) });
        sys.exit(1);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus == -1) sys.exit(0) else sys.exit(xstatus);
}

fn textwrite(s: [*:0]const u8) void {
    const pid = sys.fork() catch fail("%s: fork failed\n", .{s});
    if (pid == null) {
        @setRuntimeSafety(false);
        const addr: *allowzero volatile i32 = @ptrFromInt(0);
        addr.* = 10;
        sys.exit(1);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);
    if (xstatus == -1) sys.exit(0) else sys.exit(xstatus);
}

fn pgbug(_: [*:0]const u8) void {
    var argv = [_:null]?[*c]u8{null};
    _ = rawExec(@intFromPtr(big_arg_ptr), @ptrCast(&argv));

    @setRuntimeSafety(false);
    const p: *[2]sys.FileDescriptor = @ptrCast(@alignCast(big_arg_ptr));
    sys.pipe(p) catch {};
    sys.exit(0);
}

fn sbrkbugs(_: [*:0]const u8) void {
    var pid = sys.fork() catch fail("fork failed\n", .{});
    if (pid == null) {
        const sz = @intFromPtr(sys.sbrk(0));
        _ = sys.sbrk(-@as(i32, @intCast(sz)));
        sys.exit(0);
    }
    var st: i32 = 0;
    _ = sys.wait(&st);

    pid = sys.fork() catch fail("fork failed\n", .{});
    if (pid == null) {
        const sz = @intFromPtr(sys.sbrk(0));
        _ = sys.sbrk(-@as(i32, @intCast(sz - 3500)));
        sys.exit(0);
    }
    _ = sys.wait(&st);

    pid = sys.fork() catch fail("fork failed\n", .{});
    if (pid == null) {
        _ = sys.sbrk(@as(i32, @intCast((10 * 4096 + 2048) - @intFromPtr(sys.sbrk(0)))));
        _ = sys.sbrk(-10);
        sys.exit(0);
    }
    _ = sys.wait(&st);
    sys.exit(0);
}

fn sbrklast(_: [*:0]const u8) void {
    var top = @intFromPtr(sys.sbrk(0));
    if ((top % 4096) != 0) _ = sys.sbrk(@intCast(4096 - (top % 4096)));
    _ = sys.sbrk(4096);
    _ = sys.sbrk(10);
    _ = sys.sbrk(-20);

    top = @intFromPtr(sys.sbrk(0));
    @setRuntimeSafety(false);
    const p: [*]u8 = @ptrFromInt(top - 64);
    p[0] = 'x';
    p[1] = 0;

    const path: [*c]const u8 = @ptrCast(p);
    var fd = sys.open(path, O_RDWR | O_CREATE) catch sys.exit(1);
    _ = sys.write(fd, p[0..1]) catch 0;
    closeIgnore(fd);

    fd = sys.open(path, O_RDWR) catch sys.exit(1);
    p[0] = 0;
    _ = sys.read(fd, p[0..1]) catch 0;
    if (p[0] != 'x') sys.exit(1);
}

fn sbrk8000(_: [*:0]const u8) void {
    _ = sys.sbrk(@as(i32, @bitCast(@as(u32, 0x80000004))));
    const top = sys.sbrk(0);
    @setRuntimeSafety(false);
    const p: [*]volatile u8 = @ptrCast(top - 1);
    p[0] = p[0] +% 1;
}

fn badarg(_: [*:0]const u8) void {
    var i: usize = 0;
    while (i < 50000) : (i += 1) {
        @setRuntimeSafety(false);
        var argv = [_:null]?[*c]u8{ @ptrFromInt(0xffffffff), null };
        _ = rawExec(@intFromPtr("echo"), @ptrCast(&argv));
    }
    sys.exit(0);
}

fn bigdir(s: [*:0]const u8) void {
    const N = 500;
    var name: [10:0]u8 = [_:0]u8{0} ** 10;

    maybeUnlink("bd");

    const fd = sys.open("bd", O_CREATE) catch fail("%s: bigdir create failed\n", .{s});
    closeIgnore(fd);

    var i: usize = 0;
    while (i < N) : (i += 1) {
        name[0] = 'x';
        name[1] = @intCast('0' + (i / 64));
        name[2] = @intCast('0' + (i % 64));
        name[3] = 0;
        sys.link("bd", &name) catch fail("%s: bigdir link(bd, %s) failed\n", .{ s, &name });
    }

    maybeUnlink("bd");

    i = 0;
    while (i < N) : (i += 1) {
        name[0] = 'x';
        name[1] = @intCast('0' + (i / 64));
        name[2] = @intCast('0' + (i % 64));
        name[3] = 0;
        sys.unlink(&name) catch fail("%s: bigdir unlink failed", .{s});
    }
}

fn manywrites(s: [*:0]const u8) void {
    const nchildren = 4;
    const howmany = 30;

    var ci: usize = 0;
    while (ci < nchildren) : (ci += 1) {
        const pid = sys.fork() catch fail("fork failed\n", .{});
        if (pid == null) {
            var name: [3:0]u8 = .{ 'b', @intCast('a' + ci), 0 };
            maybeUnlink(&name);

            var iters: usize = 0;
            while (iters < howmany) : (iters += 1) {
                var i: usize = 0;
                while (i < ci + 1) : (i += 1) {
                    const fd = sys.open(&name, O_CREATE | O_RDWR) catch fail("%s: cannot create %s\n", .{ s, &name });
                    const sz = buf.len;
                    const cc = sys.write(fd, buf[0..sz]) catch 0;
                    if (cc != sz) fail("%s: write(%d) ret %d\n", .{ s, @as(i32, @intCast(sz)), @as(i32, @intCast(cc)) });
                    closeIgnore(fd);
                }
                maybeUnlink(&name);
            }

            maybeUnlink(&name);
            sys.exit(0);
        }
    }

    ci = 0;
    while (ci < nchildren) : (ci += 1) {
        var st: i32 = 0;
        _ = sys.wait(&st);
        if (st != 0) sys.exit(st);
    }
    sys.exit(0);
}

fn badwrite(_: [*:0]const u8) void {
    const assumed_free = 600;

    maybeUnlink("junk");

    var i: usize = 0;
    while (i < assumed_free) : (i += 1) {
        const fd = sys.open("junk", O_CREATE | O_WRONLY) catch fail("open junk failed\n", .{});
        _ = rawWrite(fd, 0xffffffffff, 1);
        closeIgnore(fd);
        maybeUnlink("junk");
    }

    const fd = sys.open("junk", O_CREATE | O_WRONLY) catch fail("open junk failed\n", .{});
    if ((sys.write(fd, "x") catch 0) != 1) fail("write failed\n", .{});
    closeIgnore(fd);
    maybeUnlink("junk");
    sys.exit(0);
}

fn execout(_: [*:0]const u8) void {
    var avail: usize = 0;
    while (avail < 15) : (avail += 1) {
        const pid = sys.fork() catch fail("fork failed\n", .{});
        if (pid == null) {
            while (true) {
                const a = sys.sbrk(4096);
                if (@intFromPtr(a) == 0xffffffffffffffff) break;
                @setRuntimeSafety(false);
                a[4096 - 1] = 1;
            }

            var i: usize = 0;
            while (i < avail) : (i += 1) _ = sys.sbrk(-4096);

            closeIgnore(1);
            var argv = [_:null]?[*c]u8{ @constCast("echo"), @constCast("x"), null };
            sys.exec("echo", @ptrCast(&argv)) catch {};
            sys.exit(0);
        }

        var st: i32 = 0;
        _ = sys.wait(&st);
    }
    sys.exit(0);
}

fn diskfull(s: [*:0]const u8) void {
    var fi: i32 = 0;
    var done = false;

    maybeUnlink("diskfulldir");

    while (!done) : (fi += 1) {
        var name: [32:0]u8 = [_:0]u8{0} ** 32;
        name[0] = 'b';
        name[1] = 'i';
        name[2] = 'g';
        name[3] = @intCast('0' + fi);
        name[4] = 0;
        maybeUnlink(&name);

        const fd = sys.open(&name, O_CREATE | O_RDWR | O_TRUNC) catch {
            printf("%s: could not create file %s\n", .{ s, &name });
            done = true;
            break;
        };

        var i: usize = 0;
        while (i < MAXFILE) : (i += 1) {
            if ((sys.write(fd, buf[0..BSIZE]) catch 0) != BSIZE) {
                done = true;
                closeIgnore(fd);
                break;
            }
        }
        closeIgnore(fd);
    }

    const nzz = 128;
    var i: usize = 0;
    while (i < nzz) : (i += 1) {
        var name: [32:0]u8 = [_:0]u8{0} ** 32;
        name[0] = 'z';
        name[1] = 'z';
        name[2] = @intCast('0' + (i / 32));
        name[3] = @intCast('0' + (i % 32));
        name[4] = 0;
        maybeUnlink(&name);

        const fd = sys.open(&name, O_CREATE | O_RDWR | O_TRUNC) catch break;
        closeIgnore(fd);
    }

    if (sys.mkdir("diskfulldir")) {
        printf("%s: mkdir(diskfulldir) unexpectedly succeeded!\n", .{s});
    } else |_| {}

    maybeUnlink("diskfulldir");

    i = 0;
    while (i < nzz) : (i += 1) {
        var name: [32:0]u8 = [_:0]u8{0} ** 32;
        name[0] = 'z';
        name[1] = 'z';
        name[2] = @intCast('0' + (i / 32));
        name[3] = @intCast('0' + (i % 32));
        name[4] = 0;
        maybeUnlink(&name);
    }

    var j: i32 = 0;
    while (j < fi) : (j += 1) {
        var name: [32:0]u8 = [_:0]u8{0} ** 32;
        name[0] = 'b';
        name[1] = 'i';
        name[2] = 'g';
        name[3] = @intCast('0' + j);
        name[4] = 0;
        maybeUnlink(&name);
    }
}

fn outofinodes(_: [*:0]const u8) void {
    const nzz = 32 * 32;

    var i: usize = 0;
    while (i < nzz) : (i += 1) {
        var name: [32:0]u8 = [_:0]u8{0} ** 32;
        name[0] = 'z';
        name[1] = 'z';
        name[2] = @intCast('0' + (i / 32));
        name[3] = @intCast('0' + (i % 32));
        name[4] = 0;

        maybeUnlink(&name);
        const fd = sys.open(&name, O_CREATE | O_RDWR | O_TRUNC) catch break;
        closeIgnore(fd);
    }

    i = 0;
    while (i < nzz) : (i += 1) {
        var name: [32:0]u8 = [_:0]u8{0} ** 32;
        name[0] = 'z';
        name[1] = 'z';
        name[2] = @intCast('0' + (i / 32));
        name[3] = @intCast('0' + (i % 32));
        name[4] = 0;
        maybeUnlink(&name);
    }
}

const quicktests = [_]Test{
    .{ .f = copyin, .name = "copyin" },
    .{ .f = copyout, .name = "copyout" },
    .{ .f = copyinstr1, .name = "copyinstr1" },
    .{ .f = copyinstr2, .name = "copyinstr2" },
    .{ .f = copyinstr3, .name = "copyinstr3" },
    .{ .f = rwsbrk, .name = "rwsbrk" },
    .{ .f = truncate1, .name = "truncate1" },
    .{ .f = truncate2, .name = "truncate2" },
    .{ .f = truncate3, .name = "truncate3" },
    .{ .f = openiputtest, .name = "openiput" },
    .{ .f = exitiputtest, .name = "exitiput" },
    .{ .f = iputtest, .name = "iput" },
    .{ .f = opentest, .name = "opentest" },
    .{ .f = writetest, .name = "writetest" },
    .{ .f = writebig, .name = "writebig" },
    .{ .f = createtest, .name = "createtest" },
    .{ .f = dirtest, .name = "dirtest" },
    .{ .f = exectest, .name = "exectest" },
    .{ .f = pipe1, .name = "pipe1" },
    .{ .f = killstatus, .name = "killstatus" },
    .{ .f = preempt, .name = "preempt" },
    .{ .f = exitwait, .name = "exitwait" },
    .{ .f = reparent, .name = "reparent" },
    .{ .f = twochildren, .name = "twochildren" },
    .{ .f = forkfork, .name = "forkfork" },
    .{ .f = forkforkfork, .name = "forkforkfork" },
    .{ .f = reparent2, .name = "reparent2" },
    .{ .f = mem, .name = "mem" },
    .{ .f = sharedfd, .name = "sharedfd" },
    .{ .f = fourfiles, .name = "fourfiles" },
    .{ .f = createdelete, .name = "createdelete" },
    .{ .f = unlinkread, .name = "unlinkread" },
    .{ .f = linktest, .name = "linktest" },
    .{ .f = concreate, .name = "concreate" },
    .{ .f = linkunlink, .name = "linkunlink" },
    .{ .f = subdir, .name = "subdir" },
    .{ .f = bigwrite, .name = "bigwrite" },
    .{ .f = bigfile, .name = "bigfile" },
    .{ .f = fourteen, .name = "fourteen" },
    .{ .f = rmdot, .name = "rmdot" },
    .{ .f = dirfile, .name = "dirfile" },
    .{ .f = iref, .name = "iref" },
    .{ .f = forktest, .name = "forktest" },
    .{ .f = sbrkbasic, .name = "sbrkbasic" },
    .{ .f = sbrkmuch, .name = "sbrkmuch" },
    .{ .f = kernmem, .name = "kernmem" },
    .{ .f = MAXVAplus, .name = "MAXVAplus" },
    .{ .f = sbrkfail, .name = "sbrkfail" },
    .{ .f = sbrkarg, .name = "sbrkarg" },
    .{ .f = validatetest, .name = "validatetest" },
    .{ .f = bsstest, .name = "bsstest" },
    .{ .f = bigargtest, .name = "bigargtest" },
    .{ .f = argptest, .name = "argptest" },
    .{ .f = stacktest, .name = "stacktest" },
    .{ .f = textwrite, .name = "textwrite" },
    .{ .f = pgbug, .name = "pgbug" },
    .{ .f = sbrkbugs, .name = "sbrkbugs" },
    .{ .f = sbrklast, .name = "sbrklast" },
    .{ .f = sbrk8000, .name = "sbrk8000" },
    .{ .f = badarg, .name = "badarg" },
    .{ .f = null, .name = null },
};

const slowtests = [_]Test{
    .{ .f = bigdir, .name = "bigdir" },
    .{ .f = manywrites, .name = "manywrites" },
    .{ .f = badwrite, .name = "badwrite" },
    .{ .f = execout, .name = "execout" },
    .{ .f = diskfull, .name = "diskfull" },
    .{ .f = outofinodes, .name = "outofinodes" },
    .{ .f = null, .name = null },
};

fn runTest(f: TestFn, s: [*:0]const u8) bool {
    printf("test %s: ", .{s});

    const pid = sys.fork() catch {
        fail("runtest: fork error\n", .{});
    };

    if (pid == null) {
        f(s);
        sys.exit(0);
    }

    var xstatus: i32 = 0;
    _ = sys.wait(&xstatus);

    if (xstatus != 0) {
        printf("FAILED\n", .{});
    } else {
        printf("OK\n", .{});
    }

    return xstatus == 0;
}

fn runtests(tests: []const Test, justone: ?[*:0]const u8) bool {
    for (tests) |t| {
        if (t.f == null or t.name == null) break;

        const name = t.name.?;
        if (justone == null or streqZ(justone.?, name)) {
            if (!runTest(t.f.?, name)) {
                printf("SOME TESTS FAILED\n", .{});
                return false;
            }
        }
    }
    return true;
}

// use sbrk() to count how many free physical memory pages there are.
fn countfree() i32 {
    var fds: [2]sys.FileDescriptor = undefined;
    sys.pipe(&fds) catch fail("pipe() failed in countfree()\n", .{});

    const pid = sys.fork() catch fail("fork failed in countfree()\n", .{});

    if (pid == null) {
        closeIgnore(fds[0]);

        while (true) {
            const a = sys.sbrk(4096);
            if (@intFromPtr(a) == 0xffffffffffffffff) break;

            @setRuntimeSafety(false);
            a[4096 - 1] = 1;

            if ((sys.write(fds[1], "x") catch 0) != 1) fail("write() failed in countfree()\n", .{});
        }
        sys.exit(0);
    }

    closeIgnore(fds[1]);

    var n: i32 = 0;
    var c: [1]u8 = undefined;
    while (true) {
        const cc = sys.read(fds[0], c[0..]) catch fail("read() failed in countfree()\n", .{});
        if (cc == 0) break;
        n += 1;
    }

    closeIgnore(fds[0]);
    var st: i32 = 0;
    _ = sys.wait(&st);

    return n;
}

fn drivetests(quick: bool, continuous_arg: i32, justone: ?[*:0]const u8) i32 {
    var continuous = continuous_arg;
    while (true) {
        printf("usertests starting\n", .{});
        const free0 = countfree();

        if (!runtests(quicktests[0..], justone)) {
            if (continuous != 2) return 1;
        }

        if (!quick) {
            if (justone == null) printf("usertests slow tests starting\n", .{});
            if (!runtests(slowtests[0..], justone)) {
                if (continuous != 2) return 1;
            }
        }

        const free1 = countfree();
        if (free1 < free0) {
            printf("FAILED -- lost some free pages %d (out of %d)\n", .{ free1, free0 });
            if (continuous != 2) return 1;
        }

        if (continuous == 0) break;
        if (continuous > 0) continuous = continuous_arg;
    }

    return 0;
}

pub fn main() !void {
    // This c_main mixin currently does not pass argc/argv into this Zig main().
    // Default to stock usertests behavior: run all tests once.
    const quick = false;
    const continuous: i32 = 0;
    const justone: ?[*:0]const u8 = null;

    if (drivetests(quick, continuous, justone) != 0) sys.exit(1);

    printf("ALL TESTS PASSED\n", .{});
    sys.exit(0);
}

