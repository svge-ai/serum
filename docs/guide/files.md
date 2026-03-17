# Config Files

Serum parses YAML and TOML config files into the config-file layer.

## Supported formats

| Format | Enum value | Extension |
|--------|-----------|-----------|
| YAML | `.yaml` | `.yaml`, `.yml` |
| TOML | `.toml` | `.toml` |

## Reading config

```zig
var cfg = serum.Config.init();
cfg.setConfigType(.yaml);
cfg.readConfig(
    \\host: localhost
    \\port: 8080
    \\debug: true
);

cfg.getString("host");   // "localhost"
cfg.getInt("port");      // 8080
cfg.getBool("debug");    // true
```

## TOML example

```zig
cfg.setConfigType(.toml);
cfg.readConfig(
    \\host = "localhost"
    \\port = 8080
    \\debug = true
);
```

## Nested keys

Nested YAML/TOML maps are flattened with `.` as delimiter:

```yaml
database:
  host: localhost
  port: 5432
```

Access as:

```zig
cfg.getString("database.host");  // "localhost"
cfg.getInt("database.port");     // 5432
```

## Config file search (planned)

The following API is defined but config file search from disk paths is not yet implemented:

```zig
cfg.setConfigName("config");      // name without extension
cfg.addConfigPath("/etc/myapp");  // search path
cfg.addConfigPath(".");           // current directory
```

For now, use `readConfig()` with file content you've read yourself.

## Parser limitations

The built-in parsers handle common config file patterns:

- **YAML**: key-value pairs, nested maps (one level of indentation). Does not handle arrays, multi-line strings, or complex YAML features.
- **TOML**: key-value pairs with `=`. Does not handle tables, arrays, or inline tables.

For complex config files, consider parsing externally and feeding key-value pairs via `cfg.set()`.
