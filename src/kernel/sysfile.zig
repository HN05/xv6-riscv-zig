//
// File-system system calls.
// Mostly argument checking, since we don't trust
// user code, and calls into file.c and fs.c.
//

const std = @import("std");

const sysargs = @import("sysargs.zig");
const c = sysargs.c;
const log = @import("klog.zig");

pub fn sys_dup() u64 {
    const file = sysargs.getFile(.a0) catch |err| {
        log.print("could not get file: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };

    const fd = sysargs.fileDescriptorAllocate(file) catch |err| {
        log.print("could not allocate new file descriptor: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };

    _ = c.filedup(file);
    return fd;
}

pub fn sys_read() u64 {
    const destination = sysargs.getAddress(.a1);
    const number = sysargs.getInt(.a2);

    const file = sysargs.getFile(.a0) catch |err| {
        log.print("could not get file: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };

    const result = c.fileread(file, @intFromPtr(destination), @intCast(number));
    if (result < 0) {
        return sysargs.errorVal;
    } else {
        return @intCast(result);
    }
}

pub fn sys_write() u64 {
    const source = sysargs.getAddress(.a1);
    const number = sysargs.getInt(.a2);

    const file = sysargs.getFile(.a0) catch |err| {
        log.print("could not get file: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };

    const result = c.filewrite(file, @intFromPtr(source), @intCast(number));
    if (result < 0) {
        return sysargs.errorVal;
    } else {
        return @intCast(result);
    }
}

pub fn sys_close() u64 {
    var file: *c.struct_file = undefined;
    const fd = sysargs.getFileAndDescriptor(.a0, &file) catch |err| {
        log.print("could not get file: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };

    var files = c.myproc().*.ofile;
    files[fd] = null;
    c.fileclose(file);
    return 0;
}

pub fn sys_fstat() u64 {
    const stat = sysargs.getAddress(.a1);

    const file = sysargs.getFile(.a0) catch |err| {
        log.print("could not get file: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };

    const result = c.filestat(file, @intFromPtr(stat));
    if (result < 0) {
        return sysargs.errorVal;
    } else {
        return @intCast(result);
    }
}

pub fn sys_link() u64 {
    link() catch |err| {
        log.print("could not get link: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };
    return 0;
}

const LinkErrors = error{
    FailedGetOldPath,
    FailedGetNewPath,
    FailedGetInode,
    IsDirectory,
    FailedGetParentDir,
    NotSameDevice,
    FailedUpdateNewParDir,
};

// Create the path new as a link to the same inode as old.
pub fn link() LinkErrors!void {
    var old: [c.MAXPATH]u8 = undefined;
    _ = sysargs.getString(.a0, &old) catch return LinkErrors.FailedGetOldPath;

    var new: [c.MAXPATH]u8 = undefined;
    _ = sysargs.getString(.a1, &new) catch return LinkErrors.FailedGetNewPath;

    c.begin_op();
    defer c.end_op();

    const inode = c.namei(&old) orelse return LinkErrors.FailedGetInode;
    defer c.iput(inode);

    // increment references to inode
    {
        c.ilock(inode);
        defer c.iunlock(inode);

        if (inode.*.type == c.T_DIR) return LinkErrors.IsDirectory;

        inode.*.nlink += 1;
        c.iupdate(inode);
    }

    // Roll back increment if it fails
    errdefer {
        c.ilock(inode);
        inode.*.nlink -= 1;
        c.iupdate(inode);
        c.iunlock(inode);
    }

    // update directory
    {
        var name: [c.DIRSIZ]u8 = undefined;
        const directory = c.nameiparent(&new, &name) orelse return LinkErrors.FailedGetParentDir;

        c.ilock(directory);
        defer c.iunlockput(directory);

        if (directory.*.dev != inode.*.dev) return LinkErrors.NotSameDevice;

        const result = c.dirlink(directory, &name, inode.*.inum);
        if (result < 0) return LinkErrors.FailedUpdateNewParDir;
    }
}

fn isDirectoryEmpty(directory: *c.struct_inode) bool {
    const directoryOffset = @sizeOf(c.struct_dirent);
    var index = 2; // skip past . and ..
    var directoryEntitiy: c.struct_dirent = undefined;

    while (index * directoryOffset < directory.*.size) : (index += 1) {
        const readBytes = c.readi(directory, 0, &directoryEntitiy, index * directoryOffset, directoryOffset);
        if (readBytes != directoryOffset) {
            @panic("isDirectoryEmpty: readi");
        }

        if (directoryEntitiy.inum != 0) {
            return false;
        }
    }

    return true;
}

pub fn sys_unlink() u64 {
    unlink() catch |err| {
        log.print("could not get link: {s}", .{@errorName(err)});
        return sysargs.errorVal;
    };
    return 0;
}

const UnlinkErrors = error{ FailedGetPath, FailedGetParentDir, IsDot, IsDotDot, FailedDirLookup, DirectoryNotEmpty };

pub fn unlink() UnlinkErrors!void {
    var path: [c.MAXPATH]u8 = undefined;
    _ = sysargs.getString(.a0, &path) catch return UnlinkErrors.FailedGetPath;

    c.begin_op();
    defer c.end_op();

    var name: [c.DIRSIZ]u8 = undefined;
    const directory = c.nameiparent(&path, &name) orelse return UnlinkErrors.FailedGetParentDir;

    c.ilock(directory);
    defer c.iunlockput(directory);

    if (c.namecmp(&name, ".") == 0) return UnlinkErrors.IsDot;
    if (c.namecmp(&name, "..") == 0) return UnlinkErrors.IsDotDot;

    var offset: usize = undefined;
    const inode = c.dirlookup(directory, name, &offset) orelse return UnlinkErrors.FailedDirLookup;

    c.ilock(inode);
    defer c.iunlockput(inode);

    if (inode.*.nlink < 1) {
        @panic("unlink: nlink < 1");
    }
    if (inode.*.type == c.T_DIR and !isDirectoryEmpty(inode)) return UnlinkErrors.DirectoryNotEmpty;

    // remove directory entry
    {
        var directoryEntity = std.mem.zeroes(c.struct_dirent);
        const writtenBytes = c.writei(directory, 0, @intFromPtr(&directoryEntity), offset, @sizeOf(c.struct_dirent));
        if (writtenBytes != @sizeOf(c.struct_dirent)) {
            @panic("unlink: writei");
        }
    }

    if (inode.*.type == c.T_DIR) {
        directory.*.nlink -= 1;
        c.iupdate(directory);
    }

    inode.*.nlink -= 1;
    c.iupdate(inode);
}

//
// static struct inode*
// create(char *path, short type, short major, short minor)
// {
//   struct inode *ip, *dp;
//   char name[DIRSIZ];
//
//   if((dp = nameiparent(path, name)) == 0)
//     return 0;
//
//   ilock(dp);
//
//   if((ip = dirlookup(dp, name, 0)) != 0){
//     iunlockput(dp);
//     ilock(ip);
//     if(type == T_FILE && (ip->type == T_FILE || ip->type == T_DEVICE))
//       return ip;
//     iunlockput(ip);
//     return 0;
//   }
//
//   if((ip = ialloc(dp->dev, type)) == 0){
//     iunlockput(dp);
//     return 0;
//   }
//
//   ilock(ip);
//   ip->major = major;
//   ip->minor = minor;
//   ip->nlink = 1;
//   iupdate(ip);
//
//   if(type == T_DIR){  // Create . and .. entries.
//     // No ip->nlink++ for ".": avoid cyclic ref count.
//     if(dirlink(ip, ".", ip->inum) < 0 || dirlink(ip, "..", dp->inum) < 0)
//       goto fail;
//   }
//
//   if(dirlink(dp, name, ip->inum) < 0)
//     goto fail;
//
//   if(type == T_DIR){
//     // now that success is guaranteed:
//     dp->nlink++;  // for ".."
//     iupdate(dp);
//   }
//
//   iunlockput(dp);
//
//   return ip;
//
//  fail:
//   // something went wrong. de-allocate ip.
//   ip->nlink = 0;
//   iupdate(ip);
//   iunlockput(ip);
//   iunlockput(dp);
//   return 0;
// }
//
// uint64
// sys_open(void)
// {
//   char path[MAXPATH];
//   int fd, omode;
//   struct file *f;
//   struct inode *ip;
//   int n;
//
//   argint(1, &omode);
//   if((n = argstr(0, path, MAXPATH)) < 0)
//     return -1;
//
//   begin_op();
//
//   if(omode & O_CREATE){
//     ip = create(path, T_FILE, 0, 0);
//     if(ip == 0){
//       end_op();
//       return -1;
//     }
//   } else {
//     if((ip = namei(path)) == 0){
//       end_op();
//       return -1;
//     }
//     ilock(ip);
//     if(ip->type == T_DIR && omode != O_RDONLY){
//       iunlockput(ip);
//       end_op();
//       return -1;
//     }
//   }
//
//   if(ip->type == T_DEVICE && (ip->major < 0 || ip->major >= NDEV)){
//     iunlockput(ip);
//     end_op();
//     return -1;
//   }
//
//   if((f = filealloc()) == 0 || (fd = fdalloc(f)) < 0){
//     if(f)
//       fileclose(f);
//     iunlockput(ip);
//     end_op();
//     return -1;
//   }
//
//   if(ip->type == T_DEVICE){
//     f->type = FD_DEVICE;
//     f->major = ip->major;
//   } else {
//     f->type = FD_INODE;
//     f->off = 0;
//   }
//   f->ip = ip;
//   f->readable = !(omode & O_WRONLY);
//   f->writable = (omode & O_WRONLY) || (omode & O_RDWR);
//
//   if((omode & O_TRUNC) && ip->type == T_FILE){
//     itrunc(ip);
//   }
//
//   iunlock(ip);
//   end_op();
//
//   return fd;
// }
//
// uint64
// sys_mkdir(void)
// {
//   char path[MAXPATH];
//   struct inode *ip;
//
//   begin_op();
//   if(argstr(0, path, MAXPATH) < 0 || (ip = create(path, T_DIR, 0, 0)) == 0){
//     end_op();
//     return -1;
//   }
//   iunlockput(ip);
//   end_op();
//   return 0;
// }
//
// uint64
// sys_mknod(void)
// {
//   struct inode *ip;
//   char path[MAXPATH];
//   int major, minor;
//
//   begin_op();
//   argint(1, &major);
//   argint(2, &minor);
//   if((argstr(0, path, MAXPATH)) < 0 ||
//      (ip = create(path, T_DEVICE, major, minor)) == 0){
//     end_op();
//     return -1;
//   }
//   iunlockput(ip);
//   end_op();
//   return 0;
// }
//
// uint64
// sys_chdir(void)
// {
//   char path[MAXPATH];
//   struct inode *ip;
//   struct proc *p = myproc();
//
//   begin_op();
//   if(argstr(0, path, MAXPATH) < 0 || (ip = namei(path)) == 0){
//     end_op();
//     return -1;
//   }
//   ilock(ip);
//   if(ip->type != T_DIR){
//     iunlockput(ip);
//     end_op();
//     return -1;
//   }
//   iunlock(ip);
//   iput(p->cwd);
//   end_op();
//   p->cwd = ip;
//   return 0;
// }
//
// uint64
// sys_exec(void)
// {
//   char path[MAXPATH], *argv[MAXARG];
//   int i;
//   uint64 uargv, uarg;
//
//   argaddr(1, &uargv);
//   if(argstr(0, path, MAXPATH) < 0) {
//     return -1;
//   }
//   memset(argv, 0, sizeof(argv));
//   for(i=0;; i++){
//     if(i >= NELEM(argv)){
//       goto bad;
//     }
//     if(fetchaddr(uargv+sizeof(uint64)*i, (uint64*)&uarg) < 0){
//       goto bad;
//     }
//     if(uarg == 0){
//       argv[i] = 0;
//       break;
//     }
//     argv[i] = kalloc();
//     if(argv[i] == 0)
//       goto bad;
//     if(fetchstr(uarg, argv[i], PGSIZE) < 0)
//       goto bad;
//   }
//
//   int ret = exec(path, argv);
//
//   for(i = 0; i < NELEM(argv) && argv[i] != 0; i++)
//     kfree(argv[i]);
//
//   return ret;
//
//  bad:
//   for(i = 0; i < NELEM(argv) && argv[i] != 0; i++)
//     kfree(argv[i]);
//   return -1;
// }
//
// uint64
// sys_pipe(void)
// {
//   uint64 fdarray; // user pointer to array of two integers
//   struct file *rf, *wf;
//   int fd0, fd1;
//   struct proc *p = myproc();
//
//   argaddr(0, &fdarray);
//   if(pipealloc(&rf, &wf) < 0)
//     return -1;
//   fd0 = -1;
//   if((fd0 = fdalloc(rf)) < 0 || (fd1 = fdalloc(wf)) < 0){
//     if(fd0 >= 0)
//       p->ofile[fd0] = 0;
//     fileclose(rf);
//     fileclose(wf);
//     return -1;
//   }
//   if(copyout(p->pagetable, fdarray, (char*)&fd0, sizeof(fd0)) < 0 ||
//      copyout(p->pagetable, fdarray+sizeof(fd0), (char *)&fd1, sizeof(fd1)) < 0){
//     p->ofile[fd0] = 0;
//     p->ofile[fd1] = 0;
//     fileclose(rf);
//     fileclose(wf);
//     return -1;
//   }
//   return 0;
// }
