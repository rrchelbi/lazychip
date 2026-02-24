const std = @import("std");
const opcode = @import("opcode.zig");
const Stack = @import("Stack.zig");

pub const Display = struct {
    const WIDTH = 64;
    const HEIGHT = 32;
};

const RAM_SIZE = 4096;
const NUM_REGS = 16;
const NUM_KEYS = 16;

const START_ADDR = 0x200;

const FONT_SIZE = 80;

const FONT_SET: [FONT_SIZE]u8 = .{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

pc: u16,
ram: [RAM_SIZE]u8,
display: [Display.HEIGHT * Display.WIDTH]bool,
v_reg: [NUM_REGS]u8,
i_reg: u16,
stack: Stack,
keys: [NUM_KEYS]bool,
delay_timer: u8,
sound_timer: u8,

const Engine = @This();

pub fn init() Engine {
    var engine = std.mem.zeroes(Engine);
    @memcpy(engine.ram[0..FONT_SIZE], &FONT_SET);
    engine.pc = START_ADDR;
    return engine;
}

pub fn load(engine: *Engine, data: []const u8) void {
    @memset(engine.ram[START_ADDR..data.len], data[0..]);
}

pub fn reset(engine: *Engine) void {
    @memset(engine, 0);
    @memcpy(engine.ram[0..FONT_SIZE], &FONT_SET);
    engine.pc = START_ADDR;
}

pub fn get_display(engine: *const Engine) []const bool {
    return engine.display;
}

pub fn keypress(engine: *Engine, idx: u4, pressed: bool) void {
    engine.keys[idx] = pressed;
}

pub fn tick(engine: *Engine) void {
    const op_code = engine.fetch();
    const op = opcode.parse(op_code);

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    switch (op) {
        .noop => return,
        .cls => @memset(engine.display, 0),
        .ret => {
            if (engine.stack.pop()) |ret_addr| {
                engine.pc = ret_addr;
            } else std.log.err("stack underflow on RET\n", .{});
        },
        .jmp => |nnn| engine.pc = nnn,
        .skip_eq_imm => |p| {
            if (engine.v_reg[p.x] == p.nn) engine.pc += 2;
        },
        .skip_neq_imm => |p| {
            if (engine.v_reg[p.x] != p.nn) engine.pc += 2;
        },
        .skip_eq_reg => |p| {
            if (engine.v_reg[p.x] == engine.v_reg[p.y]) engine += 2;
        },
        .skip_neq_reg => |p| {
            if (engine.v_reg[p.x] != engine.v_reg[p.y]) engine += 2;
        },
        .set_reg => |p| engine.v_reg[p.x] = p.nn,
        .add_imm => |p| engine.v_reg[p.x] +%= p.nn,
        .alu_op => |operation| {
            switch (operation.op) {
                .assign => engine.v_reg[operation.x] = engine.v_reg[operation.y],
                .@"and" => engine.v_reg[operation.x] &= engine.v_reg[operation.y],
                .@"or" => engine.v_reg[operation.x] |= engine.v_reg[operation.y],
                .xor => engine.v_reg[operation.x] ^= engine.v_reg[operation.y],
                .add => {
                    const result = @addWithOverflow(engine.v_reg[operation.x], engine.v_reg[operation.y]);
                    engine.v_reg[operation.x] = result[0];
                    engine.v_reg[0xF] = result[1];
                },
                .sub => {
                    const result = @subWithOverflow(engine.v_reg[operation.x], engine.v_reg[operation.y]);
                    engine.v_reg[operation.x] = result[0];
                    engine.v_reg[0xF] = result[1];
                },
                .subn => {
                    const result = @subWithOverflow(engine.v_reg[operation.y], engine.v_reg[operation.x]);
                    engine.v_reg[operation.x] = result[0];
                    engine.v_reg[0xF] = result[1];
                },
                .shr => {
                    const lsb = engine.v_reg[operation.x] & 1;
                    engine.v_reg >>= 1;
                    engine.v_reg[0xF] = lsb;
                },
                .shl => {
                    const msb = (engine.v_reg[operation.x] >> 7) & 1;
                    engine.v_reg <<= 1;
                    engine.v_reg[0xF] = msb;
                },
            }
        },
        .set_i => |i| engine.i_reg = i,
        .jmp_offset => |nnn| engine.pc = engine.v_reg[0] + nnn,
        .rand => |p| engine.v_reg[p.x] = prng.random().int(u8) & p.nn,
        .draw => |p| {
            const x_coord = engine.v_reg[p.x];
            const y_coord = engine.v_reg[p.y];

            // used to track pixel flip, then set the VF to 1 if flipped
            var flipped = false;
            for (0..p.n) |y_line| {
                const addr = engine.i_reg + y_line;
                const pixels = engine.ram[addr];

                for (0..8) |x_line| {
                    // get current pixel bit, only flip if != 0
                    if (pixels & (0x10000000 >> x_line) == 0) continue;

                    // wrap sprites arround screen
                    const x = (x_line + x_coord) % Engine.Display.WIDTH;
                    const y = (y_line + y_coord) % Engine.Display.HEIGHT;

                    const pixel_idx = x + Engine.Display.WIDTH * y;

                    flipped |= engine.display[pixel_idx];
                }
            }
            engine.v_reg[0xF] = if (flipped) 1 else 0;
        },
        .key_op => |p| {
            switch (p.op) {
                .skip_if_pressed => {
                    const vx = engine.v_reg[p.x];
                    if (engine.keys[vx]) engine.pc += 2;
                },
                .skip_if_not_pressed => {
                    const vx = engine.v_reg[p.x];
                    if (!engine.keys[vx]) engine.pc += 2;
                },
            }
        },
        .misc_op => |p| {
            switch (p.op) {
                .get_delay_timer => engine.v_reg[p.x] = engine.delay_timer,
                .set_delay_timer => engine.delay_timer = engine.v_reg[p.x],
                .wait_key => {
                    // If more than one key is currently being pressed, it takes the lowest indexed one.
                    var pressed = false;
                    for (0..engine.keys.len) |key_idx| {
                        if (engine.keys[key_idx]) {
                            engine.v_reg[p.x] = @as(u8, key_idx);
                            pressed = true;
                            break;
                        }
                    }

                    if (pressed) engine.pc -= 2;
                },
                .set_sound_timer => engine.sound_timer = engine.v_reg[p.x],
                .add_i => engine.i_reg +%= engine.v_reg[p.x],
                .set_i_sprite => engine.i_reg = p.x * 5,
                .bcd => {
                    const vx = engine.v_reg[p.x];
                    engine.memory[engine.i_reg] = vx / 100;
                    engine.memory[engine.i_reg + 1] = (vx / 10) % 10;
                    engine.memory[engine.i_reg + 2] = vx % 10;
                },
                .store_regs => {
                    const i = engine.i_reg;
                    for (0..p.x) |idx| engine.ram[i + idx] = engine.v_reg[idx];
                },
                .load_regs => {
                    const i = engine.i_reg;
                    for (0..p.x) |idx| engine.v_reg[idx] = engine.ram[i + idx];
                },
            }
        },
    }
}

fn fetch(engine: *Engine) u16 {
    const hb = engine.ram[engine.pc];
    const lb = engine.ram[engine.pc + 1];
    const op = @as(u16, hb) << 8 | lb;
    engine.pc += 2;
    return op;
}

pub fn tick_timers(engine: *Engine) void {
    if (engine.delay_timer > 0) engine.delay_timer -= 1;

    if (engine.sound_timer > 0) {
        if (engine.sound_timer == 1) return; // Beep
        engine.sound_timer -= 1;
    }
}
