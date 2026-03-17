# Serum

A Zig configuration library ported from Go's [spf13/viper](https://github.com/spf13/viper).

Serum provides layered configuration with a clear precedence chain, environment variable binding, and config file parsing — all in idiomatic Zig with zero heap allocations.

## Features

- **Layered precedence** — overrides > flags > env vars > config file > defaults
- **Environment variables** — explicit binding or automatic lookup with prefix
- **Config files** — YAML and TOML parsing built in
- **Type-safe getters** — `getString`, `getInt`, `getBool` with null on missing
- **Zero allocation** — fixed-size buffers, no allocator needed
- **Mamba integration** — wire CLI flags directly into the config chain

## Quick example

```zig
const serum = @import("serum");

pub fn main() !void {
    var cfg = serum.Config.init();

    // Layer 5: defaults (lowest precedence)
    cfg.setDefault("host", "localhost");
    cfg.setDefault("port", "8080");

    // Layer 4: config file
    cfg.readConfig(
        \\host: production.example.com
        \\port: 443
    );

    // Layer 3: environment variables
    cfg.setEnvPrefix("MYAPP");
    cfg.automaticEnv();  // MYAPP_HOST, MYAPP_PORT

    // Layer 1: overrides (highest precedence)
    cfg.set("host", "override.example.com");

    const host = cfg.getString("host");  // "override.example.com"
    const port = cfg.getInt("port");     // 443 (from config file)
    _ = .{ host, port };
}
```

## Precedence chain

```
1. overrides     cfg.set("key", "value")          Highest
2. flags         cfg.setFlag("key", "value")       ↑
3. env vars      MYAPP_KEY=value                   |
4. config file   key: value (YAML/TOML)            |
5. defaults      cfg.setDefault("key", "value")   Lowest
```

Each layer shadows the ones below it. Call `cfg.get("key")` and serum walks the chain top to bottom, returning the first match.

## License

MIT — same as the upstream viper project.
