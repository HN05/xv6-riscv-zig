// init: The initial user-level program
const std = @import("std");
const mixin = @import("./ulib/mixin.zig");
pub const c_main = mixin.ProgMixin.c_main;
comptime {
    @export(&c_main, .{ .name = "main", .linkage = .strong });
    @export(&c_main, .{ .name = "_start", .linkage = .strong });
}

// root overrides for std lib
pub const std_options = mixin.std_options;
pub const os = mixin.os;

const logger = std.log.scoped(.rbz);


const argv = [_][]u8{ "sh", 0 };

pub fn main() void {

}
// int
// main(void)
// {
//   int pid, wpid;
//
//   if(open("console", O_RDWR) < 0){
//     mknod("console", CONSOLE, 0);
//     open("console", O_RDWR);
//   }
//   dup(0);  // stdout
//   dup(0);  // stderr
//
//   for(;;){
//     printf("init: starting sh\n");
//     pid = fork();
//     if(pid < 0){
//       printf("init: fork failed\n");
//       exit(1);
//     }
//     if(pid == 0){
//       exec("sh", argv);
//       printf("init: exec sh failed\n");
//       exit(1);
//     }
//
//     for(;;){
//       // this call to wait() returns if the shell exits,
//       // or if a parentless process exits.
//       wpid = wait((int *) 0);
//       if(wpid == pid){
//         // the shell exited; restart it.
//         break;
//       } else if(wpid < 0){
//         printf("init: wait returned an error\n");
//         exit(1);
//       } else {
//         // it was a parentless process; do nothing.
//       }
//     }
//   }
// }
