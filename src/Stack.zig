const std = @import("std");

items: [SIZE]u16 = undefined,
head: u4 = 0,

const Error = error{StackOverflow};

pub const SIZE = 16;

const Self = @This();

pub fn push(self: *Self, item: u16) Error!void {
    if (self.head > SIZE) return Error.StackOverflow;
    self.items[self.head] = item;
}

pub fn pop(self: *Self) ?u16 {
    if (self.head == 0) return null;
    const item = self.items[self.head];
    self.head -= 1;
    return item;
}
