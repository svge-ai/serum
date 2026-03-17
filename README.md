# Serum

A Zig configuration library ported from Go's [spf13/viper](https://github.com/spf13/viper).

Layered config with precedence (defaults → config file → env → flags → overrides), environment variable binding, and YAML/TOML parsing — in idiomatic Zig with zero allocations.

## Quick start

```zig
const serum = @import("serum");

pub fn main() !void {
    var cfg = serum.Config.init();

    // Defaults (lowest precedence)
    cfg.setDefault("host", "localhost");
    cfg.setDefault("port", "8080");

    // Config file
    cfg.setConfigType(.yaml);
    cfg.readConfig("host: production.example.com\nport: 443\n");

    // Environment (overrides config file)
    cfg.setEnvPrefix("MYAPP");
    cfg.automaticEnv();  // MYAPP_HOST, MYAPP_PORT

    // Read
    const host = cfg.getString("host");
    const port = cfg.getInt("port") orelse 8080;
    _ = .{ host, port };
}
```

## Install

```bash
zig fetch --save https://github.com/svge-ai/serum/archive/refs/heads/main.tar.gz
```

Then in `build.zig`:

```zig
const serum_dep = b.dependency("serum", .{ .target = target, .optimize = optimize });
.imports = &.{
    .{ .name = "serum", .module = serum_dep.module("serum") },
},
```

Requires Zig 0.15.2+.

## Features

- **Layered precedence** — overrides > flags > env vars > config file > defaults
- **Environment variables** — explicit binding or automatic lookup with prefix
- **Config files** — YAML and TOML parsing built in
- **Type-safe getters** — `getString`, `getInt`, `getBool`
- **Zero allocation** — fixed-size buffers, no allocator
- **[Mamba](https://github.com/svge-ai/mamba) integration** — bridge CLI flags into the config chain

## Documentation

Full docs at the [Serum documentation site](https://svge-ai.github.io/serum/).

## Development

```bash
task build      # Build library
task test       # Run tests
task doc:build  # Build docs site
task doc:serve  # Serve docs locally
```

## License

MIT — same as the upstream viper project.
