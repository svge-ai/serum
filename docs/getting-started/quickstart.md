# Quick Start

## Basic usage

```zig
const serum = @import("serum");

pub fn main() !void {
    var cfg = serum.Config.init();

    // Set defaults
    cfg.setDefault("database.host", "localhost");
    cfg.setDefault("database.port", "5432");
    cfg.setDefault("debug", "false");

    // Read config file
    cfg.setConfigType(.yaml);
    cfg.readConfig(
        \\database:
        \\  host: db.example.com
        \\  port: 5432
        \\debug: true
    );

    // Read values
    const host = cfg.getString("database.host");  // "db.example.com"
    const port = cfg.getInt("database.port");      // 5432
    const debug = cfg.getBool("debug");            // true
    _ = .{ host, port, debug };
}
```

## With environment variables

```zig
var cfg = serum.Config.init();
cfg.setDefault("port", "3000");

// Bind specific keys to env vars
cfg.bindEnv("port", "PORT");

// Or auto-derive env var names with a prefix
cfg.setEnvPrefix("MYAPP");
cfg.automaticEnv();
// "database.host" → looks up MYAPP_DATABASE_HOST
```

## With overrides

```zig
var cfg = serum.Config.init();
cfg.setDefault("mode", "development");
cfg.set("mode", "production");  // overrides everything

cfg.getString("mode");  // "production"
```

## Check if a key exists

```zig
if (cfg.isSet("database.host")) {
    // key exists at some precedence level
}
```
