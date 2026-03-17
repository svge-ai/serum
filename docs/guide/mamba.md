# Using with Mamba

Serum and [Mamba](https://github.com/svge-ai/mamba) are designed to work together, mirroring the viper + cobra pattern from Go.

Mamba handles CLI argument parsing; serum handles configuration. Wire them together by feeding mamba's parsed flag values into serum's flag layer.

## Pattern

```zig
const mamba = @import("mamba");
const serum = @import("serum");

var cfg = serum.Config.init();

fn run(cmd: *mamba.Command, _: []const []const u8) !void {
    // Bridge mamba flags → serum config
    cfg.setFlag("port", cmd.getFlag([]const u8, "port"));
    cfg.setFlag("host", cmd.getFlag([]const u8, "host"));

    // Now serum's precedence chain applies:
    // CLI flag > env var > config file > default
    const port = cfg.getInt("port") orelse 8080;
    const host = cfg.getString("host");
    _ = .{ port, host };
}

pub fn main() !void {
    // Serum: set defaults and read config
    cfg.setDefault("host", "localhost");
    cfg.setDefault("port", "8080");
    cfg.setEnvPrefix("MYAPP");
    cfg.automaticEnv();

    // Mamba: define CLI
    var cmd = mamba.Command.init(.{
        .name = "serve",
        .short = "Start the server",
        .flags = &.{
            mamba.Flag.string("host", 'H', "Bind address", ""),
            mamba.Flag.string("port", 'p', "Listen port", ""),
        },
        .run = &run,
    });
    try cmd.execute();
}
```

## Precedence with mamba

When using both libraries:

```
1. cfg.set()            Runtime overrides
2. cfg.setFlag()        ← mamba CLI flags go here
3. env vars             MYAPP_PORT=9090
4. config file          port: 8080
5. cfg.setDefault()     Sensible fallbacks
```

A user running `myapp --port 3000` overrides the config file and env var. Setting `MYAPP_PORT=9090` overrides the config file but not the CLI flag.

## Build configuration

Add both dependencies to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/svge-ai/mamba/archive/refs/heads/main.tar.gz
zig fetch --save https://github.com/svge-ai/serum/archive/refs/heads/main.tar.gz
```

And wire both into your executable's imports in `build.zig`:

```zig
.imports = &.{
    .{ .name = "mamba", .module = mamba_dep.module("mamba") },
    .{ .name = "serum", .module = serum_dep.module("serum") },
},
```
