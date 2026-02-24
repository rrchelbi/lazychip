const std = @import("std");

pub const Opcode = union(enum) {
    // Control flow (0x0___)
    noop,
    cls, // 0x00E0
    ret, // 0x00EE

    // Jumps and calls
    jmp: u12, // 0x1NNN
    call: u12, // 0x2NNN
    jmp_offset: u12, // 0xBNNN (V0 + NNN)

    // Conditionals
    skip_eq_imm: struct { x: u4, nn: u8 }, // 0x3XNN
    skip_neq_imm: struct { x: u4, nn: u8 }, // 0x4XNN
    skip_eq_reg: struct { x: u4, y: u4 }, // 0x5XY0
    skip_neq_reg: struct { x: u4, y: u4 }, // 0x9XY0

    // Register operations
    set_reg: struct { x: u4, nn: u8 }, // 0x6XNN
    add_imm: struct { x: u4, nn: u8 }, // 0x7XNN
    alu_op: struct { x: u4, y: u4, op: AluOp }, // 0x8XY_

    // Memory
    set_i: u12, // 0xANNN

    // Random
    rand: struct { x: u4, nn: u8 }, // 0xCXNN

    // Drawing
    draw: struct { x: u4, y: u4, n: u4 }, // 0xDXYN

    // Input/Timers
    key_op: struct { x: u4, op: KeyOp }, // 0xEX__
    misc_op: struct { x: u4, op: MiscOp }, // 0xFX__

    invalid: u16,
};

pub const AluOp = enum(u4) {
    /// 8XY0: VX = VY
    assign = 0x0,

    /// 8XY1: VX |= VY
    @"or" = 0x1,

    /// 8XY2: VX &= VY
    @"and" = 0x2,

    /// 8XY3: VX ^= VY
    xor = 0x3,

    /// 8XY4: VX += VY (set VF = carry)
    add = 0x4,

    /// 8XY5: VX -= VY (set VF = NOT borrow)
    sub = 0x5,

    /// 8XY6: VX >>= 1 (VF = LSB)
    shr = 0x6,

    /// 8XY7: VX = VY - VX
    subn = 0x7,

    /// 8XYE: VX <<= 1 (VF = MSB)
    shl = 0xE,
};

pub const KeyOp = enum(u8) {
    skip_if_pressed = 0x9E, // EX9E
    skip_if_not_pressed = 0xA1, // EXA1
};

pub const MiscOp = enum(u8) {
    get_delay_timer = 0x07, // FX07: delay_timer = VX
    set_delay_timer = 0x15, // FX15: delay_timer = VX
    wait_key = 0x0A, // FX0A: wait for key press
    set_sound_timer = 0x18, // FX18: sound_timer = VX
    add_i = 0x1E, // FX1E: I += VX
    set_i_sprite = 0x29, // FX29: I = sprite location of VX
    bcd = 0x33, // FX33: store BCD of VX in [I:I+2]
    store_regs = 0x55, // FX55: store V0-VX in memory at I
    load_regs = 0x65, // FX65: load V0-VX from memory at I
};

/// Parse a 16-bit opcode into structured format
pub fn parse(opcode: u16) Opcode {
    // Extract nibbles
    const n1 = @as(u4, @truncate(opcode >> 12));
    const n2 = @as(u4, @truncate(opcode >> 8));
    const n3 = @as(u4, @truncate(opcode >> 4));
    const n4 = @as(u4, @truncate(opcode >> 0));

    // Extract common fields
    const nnn = @as(u12, @truncate(opcode & 0x0FFF));
    const nn = @as(u8, @truncate(opcode & 0x00FF));
    const x = n2;
    const y = n3;
    const n = n4;

    return switch (n1) {
        0x0 => switch (opcode) {
            0x00E0 => .cls,
            0x00EE => .ret,
            else => .noop,
        },
        0x1 => .{ .jmp = nnn },
        0x2 => .{ .call = nnn },
        0x3 => .{ .skip_eq_imm = .{ .x = x, .nn = nn } },
        0x4 => .{ .skip_neq_imm = .{ .x = x, .nn = nn } },
        0x5 => if (n4 == 0)
            .{ .skip_eq_reg = .{ .x = x, .y = y } }
        else
            .{ .invalid = opcode },
        0x6 => .{ .set_reg = .{ .x = x, .nn = nn } },
        0x7 => .{ .add_imm = .{ .x = x, .nn = nn } },
        0x8 => {
            const alu_op = @as(AluOp, @enumFromInt(n4));
            return .{ .alu_op = .{ .x = x, .y = y, .op = alu_op } };
        },
        0x9 => if (n4 == 0)
            .{ .skip_neq_reg = .{ .x = x, .y = y } }
        else
            .{ .invalid = opcode },
        0xA => .{ .set_i = nnn },
        0xB => .{ .jmp_offset = nnn },
        0xC => .{ .rand = .{ .x = x, .nn = nn } },
        0xD => .{ .draw = .{ .x = x, .y = y, .n = n } },
        0xE => if (nn == 0x9E)
            .{ .key_op = .{ .x = x, .op = .skip_if_pressed } }
        else if (nn == 0xA1)
            .{ .key_op = .{ .x = x, .op = .skip_if_not_pressed } }
        else
            .{ .invalid = opcode },
        0xF => switch (nn) {
            0x07 => .{ .misc_op = .{ .x = x, .op = .get_delay_timer } },
            0x15 => .{ .misc_op = .{ .x = x, .op = .set_delay_timer } },
            0x0A => .{ .misc_op = .{ .x = x, .op = .wait_key } },
            0x18 => .{ .misc_op = .{ .x = x, .op = .set_sound_timer } },
            0x1E => .{ .misc_op = .{ .x = x, .op = .add_i } },
            0x29 => .{ .misc_op = .{ .x = x, .op = .set_i_sprite } },
            0x33 => .{ .misc_op = .{ .x = x, .op = .bcd } },
            0x55 => .{ .misc_op = .{ .x = x, .op = .store_regs } },
            0x65 => .{ .misc_op = .{ .x = x, .op = .load_regs } },
            else => .{ .invalid = opcode },
        },
        else => .{ .invalid = opcode },
    };
}
