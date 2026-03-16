# Serum

Zig configuration library, inspired by Go's [viper](https://github.com/spf13/viper).

## Features

- Config precedence: defaults → config file → env vars → flags → overrides
- YAML and TOML config reading
- Environment variable binding with prefix
- Nested key access (`get("a.b.c")`)
- Type-safe getters (getString, getInt, getBool)

## Usage

```zig
const serum = @import("serum");

var cfg = serum.Config.init();
cfg.setDefault("server.port", "8080");
cfg.bindEnv("server.port", "PORT");
cfg.setConfigType(.toml);

const port = cfg.getString("server.port");
```

## License

Apache-2.0
