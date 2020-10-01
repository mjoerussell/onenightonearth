// Trying to prep for eventually having multiple target platforms (web, android, etc).
// This currently makes main.zig redunant, but that's ok. In the future main.zig will do
// the work of any standard initialization plus selecting target platforms.
usingnamespace @import("./wasm_interface.zig");
