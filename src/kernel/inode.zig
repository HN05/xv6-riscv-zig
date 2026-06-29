const SleepLock = @import("sleeplock.zig");
const Device = @import("device.zig");
const fs = @import("filesystem.zig");
const SpinLock = @import("spinlock.zig");
const common = @import("common");
const Buffer = @import("buffer.zig");
const std = @import("std");
const log = @import("log.zig");

// Inodes.
//
// An inode describes a single unnamed file.
// The inode disk structure holds metadata: the file's type,
// its size, the number of links referring to it, and the
// list of blocks holding the file's content.
//
// The inodes are laid out sequentially on disk at block
// sb.inodestart. Each inode has a number, indicating its
// position on the disk.
//
// The kernel keeps a table of in-use inodes in memory
// to provide a place for synchronizing access
// to inodes used by multiple processes. The in-memory
// inodes include book-keeping information that is
// not stored on disk: ip->ref and ip->valid.
//
// An inode and its in-memory representation go through a
// sequence of states before they can be used by the
// rest of the file system code.
//
// * Allocation: an inode is allocated if its type (on disk)
//   is non-zero. ialloc() allocates, and iput() frees if
//   the reference and link counts have fallen to zero.
//
// * Referencing in table: an entry in the inode table
//   is free if ip->ref is zero. Otherwise ip->ref tracks
//   the number of in-memory pointers to the entry (open
//   files and current directories). iget() finds or
//   creates a table entry and increments its ref; iput()
//   decrements ref.
//
// * Valid: the information (type, size, &c) in an inode
//   table entry is only correct when ip->valid is 1.
//   ilock() reads the inode from
//   the disk and sets ip->valid, while iput() clears
//   ip->valid if ip->ref has fallen to zero.
//
// * Locked: file system code may only examine and modify
//   the information in an inode and its content if it
//   has first locked the inode.
//
// Thus a typical sequence is:
//   ip = iget(dev, inum)
//   ilock(ip)
//   ... examine and modify ip->xxx ...
//   iunlock(ip)
//   iput(ip)
//
// ilock() is separate from iget() so that system calls can
// get a long-term reference to an inode (as for an open file)
// and only lock it for short periods (e.g., in read()).
// The separation also helps avoid deadlock and races during
// pathname lookup. iget() increments ip->ref so that the inode
// stays in the table and pointers to it remain valid.
//
// Many internal file system functions expect the caller to
// have locked the inodes involved; this lets callers create
// multi-step atomic operations.
//
// The itable.lock spin-lock protects the allocation of itable
// entries. Since ip->ref indicates whether an entry is free,
// and ip->dev and ip->inum indicate which i-node an entry
// holds, one must hold itable.lock while using any of those fields.
//
// An ip->lock sleep-lock protects all ip-> fields other than ref,
// dev, and inum.  One must hold ip->lock in order to
// read or write that inode's ip->valid, ip->size, ip->type, &c.

const Inode = @This();

pub const direct_inode_pointer_num = 12;
pub const indirect_inode_pointer_num = fs.block_size / @sizeOf(u32);
pub const inode_address_count = direct_inode_pointer_num + 1;
pub const inodes_per_block = fs.block_size / @sizeOf(DiskInode);
pub const max_block_file_size = direct_inode_pointer_num + indirect_inode_pointer_num;

// Block containing inode i
fn getInodeBlock(inode_number: u32) u32 {
    return inode_number / inodes_per_block + fs.superBlock.inodestart;
}

// in-memory inode identity
filesystem_device: Device.ID = .zero,
inode_number: u32 = 0,
reference_count: u32 = 0,

sleep_lock: SleepLock = .{ .name = "inode" },
is_valid: bool = false,

disk_inode: DiskInode = .{},

// On-disk inode structure
pub const DiskInode = extern struct {
    type: fs.FileType = .free, // File type
    device: Device.ID = .zero,
    link_count: u16 = 0, // Number of links to inode in file system
    size: u32 = 0, // Size of file (bytes)
    addrs: [inode_address_count]u32 = [_]u32{0} ** inode_address_count, // Data block addresses
};

const DiskInodeBlock = [inodes_per_block]DiskInode;

pub fn reset(self: *Inode) void {
    self.* = .{};
    self.disk_inode.reset();
}

pub const InodeTable = struct {
    lock: SpinLock = .{ .name = "inode_table" },
    inodes: [common.param.NINODE]Inode = [_]Inode{.{}} ** common.param.NINODE,
};

var inode_table: InodeTable = .{};

fn getDiskInode(buffer: *Buffer, inode_number: u32) *DiskInode {
    const disk_inodes = std.mem.bytesAsValue(
        DiskInodeBlock,
        buffer.data[0..@sizeOf(DiskInodeBlock)],
    );

    const inode_index = inode_number % inodes_per_block;
    return &disk_inodes.*[inode_index];
}

// Allocate an inode on device dev.
// Mark it as allocated by  giving it type type.
// Returns an unlocked but allocated and referenced inode,
// or NULL if there is no free inode.
pub fn alloc(device: Device.ID, file_type: fs.FileType) !*Inode {
    for (0..fs.superBlock.ninodes) |inode_number| {
        const buffer = Buffer.read(device, getInodeBlock(inode_number));
        defer buffer.release();

        const disk_inode = getDiskInode(buffer, inode_number);

        if (disk_inode.type == .free) { // free inode
            disk_inode = .{}; // reset it
            disk_inode.type = file_type;
            log.write(buffer); // mark it allocated on the disk
            return get(device, inode_number);
        }
    }
    return error.OutOfInodes;
}

// Copy a modified in-memory inode to disk.
// Must be called after every change to an ip->xxx field
// that lives on disk.
// Caller must hold ip->lock.
pub fn update(inode: *Inode) void {
    const buffer = Buffer.read(inode.filesystem_device, getInodeBlock(inode.inode_number));
    defer buffer.release();

    const disk_inode = getDiskInode(buffer, inode.inode_number);
    disk_inode.* = inode.disk_inode;
    log.write(buffer);
}

// Find the inode with number inum on device dev
// and return the in-memory copy. Does not lock
// the inode and does not read it from disk.
fn get(device: Device, inode_number: u32) *Inode {
    inode_table.lock.acquire();
    defer inode_table.lock.release();

    // Is the inode already in the table?
    var empty_inode: ?*Inode = null;
    for (inode_table.inodes) |inode| {
        if (inode.reference_count > 0 and inode.filesystem_device == device and inode.inode_number == inode_number) {
            inode.reference_count += 1;
            return inode;
        }
        if (empty_inode == null and inode.reference_count == 0) {
            empty_inode = inode; // remember empty slot
        }
    }

    if (empty_inode == null) @panic("no inodes available");

    // Recycle an inode entry.
    const found_inode = empty_inode.?;
    found_inode.filesystem_device = device;
    found_inode.inode_number = inode_number;
    found_inode.reference_count = 1;
    found_inode.is_valid = false;
    return found_inode;
}

// Increment reference count for ip.
// Returns ip to enable ip = idup(ip1) idiom.
pub fn duplicate(inode: *Inode) *Inode {
    inode_table.lock.acquire();
    defer inode_table.lock.release();

    inode.reference_count += 1;
    return inode;
}

// Lock the given inode.
// Reads the inode from disk if necessary.
pub fn lock(inode: *Inode) void {
    if (inode.reference_count < 1) @panic("can't lock unused inode");

    inode.sleep_lock.acquire();

    if (!inode.is_valid) {
        const buffer = Buffer.read(inode.filesystem_device, getInodeBlock(inode.inode_number));
        defer buffer.release();

        const disk_inode = getDiskInode(buffer, inode.inode_number);
        inode.disk_inode = disk_inode.*;
        inode.is_valid = true;
        if (inode.disk_inode.type == .free) @panic("ilock: no type");
    }
}

// Unlock the given inode.
pub fn release(inode: *Inode) void {
    if (!inode.sleep_lock.isHolding()) @panic("not holding inode lock");
    if (inode.reference_count < 1) @panic("can't unlock unused inode");

    inode.sleep_lock.release();
}

// Drop a reference to an in-memory inode.
// If that was the last reference, the inode table entry can
// be recycled.
// If that was the last reference and the inode has no links
// to it, free the inode (and its content) on disk.
// All calls to iput() must be inside a transaction in
// case it has to free the inode.
pub fn put(inode: *Inode) void {
    inode_table.lock.acquire();
    defer inode_table.lock.release();

    if (inode.reference_count == 1 and inode.is_valid and inode.disk_inode.link_count == 0) {
        // inode has no links and no other references: truncate and free.
        inode_table.lock.release();
        defer inode_table.lock.acquire();

        // ip->ref == 1 means no other process can have ip locked,
        // so this acquiresleep() won't block (or deadlock).
        inode.sleep_lock.acquire();
        defer inode.sleep_lock.release();

        inode.truncate();
        inode.disk_inode.type = .free;
        inode.update();
        inode.is_valid = false;
    }

    inode.reference_count -= 1;
}

// Common idiom: unlock, then put.
pub fn releasePut(inode: *Inode) void {
    inode.release();
    inode.put();
}

// Inode content
//
// The content (data) associated with each inode is stored
// in blocks on the disk. The first NDIRECT block numbers
// are listed in ip->addrs[].  The next NINDIRECT blocks are
// listed in block ip->addrs[NDIRECT].

// Return the disk block address of the nth block in inode ip.
// If there is no such block, bmap allocates one.
// returns 0 if out of disk space.



// static uint
// bmap(struct inode *ip, uint bn)
// {
//   uint addr, *a;
//   struct buf *bp;
//
//   if(bn < NDIRECT){
//     if((addr = ip->addrs[bn]) == 0){
//       addr = balloc(ip->dev);
//       if(addr == 0)
//         return 0;
//       ip->addrs[bn] = addr;
//     }
//     return addr;
//   }
//   bn -= NDIRECT;
//
//   if(bn < NINDIRECT){
//     // Load indirect block, allocating if necessary.
//     if((addr = ip->addrs[NDIRECT]) == 0){
//       addr = balloc(ip->dev);
//       if(addr == 0)
//         return 0;
//       ip->addrs[NDIRECT] = addr;
//     }
//     bp = bread(ip->dev, addr);
//     a = (uint*)bp->data;
//     if((addr = a[bn]) == 0){
//       addr = balloc(ip->dev);
//       if(addr){
//         a[bn] = addr;
//         log_write(bp);
//       }
//     }
//     brelse(bp);
//     return addr;
//   }
//
//   panic("bmap: out of range");
// }
//
// // Truncate inode (discard contents).
// // Caller must hold ip->lock.
// void
// itrunc(struct inode *ip)
// {
//   int i, j;
//   struct buf *bp;
//   uint *a;
//
//   for(i = 0; i < NDIRECT; i++){
//     if(ip->addrs[i]){
//       bfree(ip->dev, ip->addrs[i]);
//       ip->addrs[i] = 0;
//     }
//   }
//
//   if(ip->addrs[NDIRECT]){
//     bp = bread(ip->dev, ip->addrs[NDIRECT]);
//     a = (uint*)bp->data;
//     for(j = 0; j < NINDIRECT; j++){
//       if(a[j])
//         bfree(ip->dev, a[j]);
//     }
//     brelse(bp);
//     bfree(ip->dev, ip->addrs[NDIRECT]);
//     ip->addrs[NDIRECT] = 0;
//   }
//
//   ip->size = 0;
//   iupdate(ip);
// }
