const Device = @import("device.zig");
const Buffer = @import("buffer.zig");
const log = @import("log.zig");
const std = @import("std");
const Inode = @import("inode.zig");

pub const FileType = enum(u16) { free = 0, directory = 1, file = 2, device = 3 };

pub const FileStatus = extern struct {
    device: Device.ID,
    inode_number: u32,
    type: FileType,
    link_count: u16,
    size: u64,
};

pub const root_inode_number = 1;
pub const block_size = 1024;
pub const fs_magic = 0x10203040;

// Disk layout:
// [ boot block | super block | log | inode blocks |
//                                          free bit map | data blocks]
//
// mkfs computes the super block and builds an initial file system. The
// super block describes the disk layout:
pub const SuperBlock = struct {
    magic: u32, // Must be FSMAGIC
    size: u32, // Size of file system image (blocks)
    nblocks: u32, // Number of data blocks
    ninodes: u32, // Number of inodes.
    nlog: u32, // Number of log blocks
    logstart: u32, // Block number of first log block
    inodestart: u32, // Block number of first inode block
    bmapstart: u32, // Block number of first free map block
};

const BlockBitmap = struct {
    bytes: []u8,

    pub fn isUsed(self: BlockBitmap, bit_index: usize) bool {
        const byte_index = bit_index / 8;
        const bit_offset: u3 = bit_index % 8;
        const mask: u8 = @as(u8, 1) << bit_offset;

        return (self.bytes[byte_index] & mask) != 0;
    }

    pub fn markUsed(self: BlockBitmap, bit_index: usize) void {
        const byte_index = bit_index / 8;
        const bit_offset: u3 = bit_index % 8;
        const mask: u8 = @as(u8, 1) << bit_offset;

        self.bytes[byte_index] |= mask;
    }

    pub fn markFree(self: BlockBitmap, bit_index: usize) void {
        if (isUsed(self, bit_index)) @panic("trying to free used block");
        const byte_index = bit_index / 8;
        const bit_offset: u3 = bit_index % 8;
        const mask: u8 = @as(u8, 1) << bit_offset;

        self.bytes[byte_index] &= ~mask;
    }

    pub fn findFree(self: BlockBitmap, max_bits: u32) ?usize {
        var bit_index: usize = 0;
        while (bit_index < max_bits) : (bit_index += 1) {
            if (!self.isUsed(bit_index)) return bit_index;
        }
        return null;
    }
};

// Bitmap bits per block
pub const bitmap_bits_per_block = block_size * 8;

// Block of free map containing bit for block b
fn getFreeMapBlock(block: u32) u32 {
    return block / bitmap_bits_per_block + superBlock.bmapstart;
}

// Directory is a file containing a sequence of dirent structures.

pub const DirectoryEntry = extern struct {
    i_num: u16,
    name: [max_name_length]u8,

    pub const max_name_length = 14;
};

// File system implementation.  Five layers:
//   + Blocks: allocator for raw disk blocks.
//   + Log: crash recovery for multi-step updates.
//   + Files: inode allocator, reading, writing, metadata.
//   + Directories: inode with special contents (list of other inodes!)
//   + Names: paths like /usr/rtm/xv6/fs.c for convenient naming.
//
// This file contains the low-level file system manipulation
// routines.  The (higher-level) system call implementations
// are in sysfile.c.

// there should be one superblock per disk device, but we run with
// only one device
pub var superBlock: SuperBlock = undefined;

// Read the super block.
fn readSuperBlock(device: Device.ID, superBlockDestination: *SuperBlock) void {
    const buffer = Buffer.read(device, 1);
    defer buffer.release();

    @memmove(
        std.mem.asBytes(superBlockDestination.*),
        buffer.data[0..@sizeOf(SuperBlock)],
    );
}

// Init fs
pub fn init(device: Device.ID) void {
    readSuperBlock(device, &superBlock);
    if (superBlock.magic != fs_magic) @panic("invalid file system");
    log.init(device, superBlock);
}

// Zero a block.
fn zeroBlock(device: Device.ID, block_number: u32) void {
    const buffer = Buffer.read(device, block_number);
    defer buffer.release();

    @memset(&buffer.data, 0);
    log.write(buffer);
}

// Blocks.

// Allocate a zeroed disk block.
pub fn blockAllocate(device: Device.ID) !u32 {
    var block_number = 0;
    while (block_number < superBlock.size) : (block_number += bitmap_bits_per_block) {
        var allocated_block: ?u32 = null;
        {
            const buffer = Buffer.read(device, getFreeMapBlock(block_number));
            defer buffer.release();

            const bitmap = BlockBitmap{
                .bytes = buffer.data[0..],
            };

            const remaining_blocks = superBlock.size - block_number;
            const max_blocks = @min(bitmap_bits_per_block, remaining_blocks);

            if (bitmap.findFree(max_blocks)) |block_index| {
                bitmap.markUsed(block_index);
                log.write(buffer);

                allocated_block = block_number + block_index;
            }
        }
        if (allocated_block) |block| {
            zeroBlock(device, block);
            return block;
        }
    }
    return error.OutOfBlocks;
}

// Free a disk block.
pub fn blockFree(device: Device.ID, block_number: u32) void {
    const buffer = Buffer.read(device, getFreeMapBlock(block_number));
    defer buffer.release();

    const bitmap = BlockBitmap{
        .bytes = buffer.data[0..],
    };

    const block_offset = block_number % bitmap_bits_per_block;

    bitmap.markFree(block_offset);
    log.write(buffer);
}

// // Directories
//
// int
// namecmp(const char *s, const char *t)
// {
//   return strncmp(s, t, DIRSIZ);
// }
//
// // Look for a directory entry in a directory.
// // If found, set *poff to byte offset of entry.
// struct inode*
// dirlookup(struct inode *dp, char *name, uint *poff)
// {
//   uint off, inum;
//   struct dirent de;
//
//   if(dp->type != T_DIR)
//     panic("dirlookup not DIR");
//
//   for(off = 0; off < dp->size; off += sizeof(de)){
//     if(readi(dp, 0, (uint64)&de, off, sizeof(de)) != sizeof(de))
//       panic("dirlookup read");
//     if(de.inum == 0)
//       continue;
//     if(namecmp(name, de.name) == 0){
//       // entry matches path element
//       if(poff)
//         *poff = off;
//       inum = de.inum;
//       return iget(dp->dev, inum);
//     }
//   }
//
//   return 0;
// }
//
// // Write a new directory entry (name, inum) into the directory dp.
// // Returns 0 on success, -1 on failure (e.g. out of disk blocks).
// int
// dirlink(struct inode *dp, char *name, uint inum)
// {
//   int off;
//   struct dirent de;
//   struct inode *ip;
//
//   // Check that name is not present.
//   if((ip = dirlookup(dp, name, 0)) != 0){
//     iput(ip);
//     return -1;
//   }
//
//   // Look for an empty dirent.
//   for(off = 0; off < dp->size; off += sizeof(de)){
//     if(readi(dp, 0, (uint64)&de, off, sizeof(de)) != sizeof(de))
//       panic("dirlink read");
//     if(de.inum == 0)
//       break;
//   }
//
//   strncpy(de.name, name, DIRSIZ);
//   de.inum = inum;
//   if(writei(dp, 0, (uint64)&de, off, sizeof(de)) != sizeof(de))
//     return -1;
//
//   return 0;
// }
//
// // Paths
//
// // Copy the next path element from path into name.
// // Return a pointer to the element following the copied one.
// // The returned path has no leading slashes,
// // so the caller can check *path=='\0' to see if the name is the last one.
// // If no name to remove, return 0.
// //
// // Examples:
// //   skipelem("a/bb/c", name) = "bb/c", setting name = "a"
// //   skipelem("///a//bb", name) = "bb", setting name = "a"
// //   skipelem("a", name) = "", setting name = "a"
// //   skipelem("", name) = skipelem("////", name) = 0
// //
// static char*
// skipelem(char *path, char *name)
// {
//   char *s;
//   int len;
//
//   while(*path == '/')
//     path++;
//   if(*path == 0)
//     return 0;
//   s = path;
//   while(*path != '/' && *path != 0)
//     path++;
//   len = path - s;
//   if(len >= DIRSIZ)
//     memmove(name, s, DIRSIZ);
//   else {
//     memmove(name, s, len);
//     name[len] = 0;
//   }
//   while(*path == '/')
//     path++;
//   return path;
// }
//
// // Look up and return the inode for a path name.
// // If parent != 0, return the inode for the parent and copy the final
// // path element into name, which must have room for DIRSIZ bytes.
// // Must be called inside a transaction since it calls iput().
// static struct inode*
// namex(char *path, int nameiparent, char *name)
// {
//   struct inode *ip, *next;
//
//   if(*path == '/')
//     ip = iget(ROOTDEV, ROOTINO);
//   else
//     ip = idup(myproc()->cwd);
//
//   while((path = skipelem(path, name)) != 0){
//     ilock(ip);
//     if(ip->type != T_DIR){
//       iunlockput(ip);
//       return 0;
//     }
//     if(nameiparent && *path == '\0'){
//       // Stop one level early.
//       iunlock(ip);
//       return ip;
//     }
//     if((next = dirlookup(ip, name, 0)) == 0){
//       iunlockput(ip);
//       return 0;
//     }
//     iunlockput(ip);
//     ip = next;
//   }
//   if(nameiparent){
//     iput(ip);
//     return 0;
//   }
//   return ip;
// }
//
// struct inode*
// namei(char *path)
// {
//   char name[DIRSIZ];
//   return namex(path, 0, name);
// }
//
// struct inode*
// nameiparent(char *path, char *name)
// {
//   return namex(path, 1, name);
// }
//
