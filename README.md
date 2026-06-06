# lazychip

A [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) emulator engine written in Zig.

## Overview

lazychip implements the core CHIP-8 virtual machine as a reusable library (`lazychiplib`), exposing an `Engine` struct that manages the full interpreter state: 4KB RAM, 16 general-purpose registers, an index register, a program counter, a 64×32 pixel display, a 16-key input state, delay/sound timers, and a 16-level call stack.

The opcode parser handles the complete CHIP-8 instruction set, including control flow, ALU operations, drawing, input handling, timers, and BCD encoding.

## Requirements

- Zig `0.16.0-dev.2535` or newer (nightly build)

## Build

```sh
zig build
```

Run the executable:

```sh
zig build run
```

## Project structure

```
src/
  root.zig      # Library root — re-exports Engine
  Engine.zig    # Core VM: state, tick loop, fetch/decode/execute
  opcode.zig    # Opcode type definitions and parser
  Stack.zig     # Fixed-size 16-entry call stack
  main.zig      # Entry point (demo / test harness)
```

## Using as a library

Add `lazychiplib` as a module dependency in your `build.zig`, then:

```zig
const lazychip = @import("lazychiplib");
const Engine = lazychip.Engine;

var emu: Engine = .init();
emu.load(rom_bytes);   // load a CHIP-8 ROM

// main loop
while (running) {
    emu.tick();             // execute one instruction
    emu.tick_timers();      // decrement delay/sound timers
    render(emu.get_display());
    handle_input(&emu);
}
```

Key API:

| Function                        | Description                                          |
| ------------------------------- | ---------------------------------------------------- |
| `Engine.init()`                 | Initialize emulator with font data loaded            |
| `engine.load(data)`             | Load a ROM into memory at `0x200`                    |
| `engine.tick()`                 | Fetch, decode, and execute one instruction           |
| `engine.tick_timers()`          | Decrement delay and sound timers                     |
| `engine.get_display()`          | Return the 64×32 pixel framebuffer as `[]const bool` |
| `engine.keypress(idx, pressed)` | Update key state                                     |
| `engine.reset()`                | Reset all state and reload fonts                     |

## Status

Work in progress. The engine covers the full standard CHIP-8 instruction set. A frontend (display rendering, audio, input handling) is not yet included.

## License

MIT
