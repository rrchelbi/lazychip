const std = @import("std");
const lazychip = @import("lazychiplib");
const Engine = lazychip.Engine;

pub fn main() !void {
    var emulator: Engine = .init();
    try emulator.stack.push(1);
    _ = emulator.stack.pop();

    std.debug.print("{}\n", .{emulator});
}
