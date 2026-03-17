# Viper Migration Guide

Serum mirrors viper's API. This guide shows side-by-side equivalents.

## Initialization

=== "Viper (Go)"

    ```go
    viper.SetDefault("port", "8080")
    viper.SetConfigName("config")
    viper.SetConfigType("yaml")
    viper.AddConfigPath("/etc/myapp")
    viper.AddConfigPath(".")
    viper.ReadInConfig()
    ```

=== "Serum (Zig)"

    ```zig
    var cfg = serum.Config.init();
    cfg.setDefault("port", "8080");
    cfg.setConfigName("config");
    cfg.setConfigType(.yaml);
    cfg.addConfigPath("/etc/myapp");
    cfg.addConfigPath(".");
    cfg.readConfig(file_content);  // read file yourself for now
    ```

## Getting values

=== "Viper (Go)"

    ```go
    host := viper.GetString("database.host")
    port := viper.GetInt("database.port")
    debug := viper.GetBool("debug")
    ```

=== "Serum (Zig)"

    ```zig
    const host = cfg.getString("database.host");
    const port = cfg.getInt("database.port");
    const debug = cfg.getBool("debug");
    ```

## Setting values

=== "Viper (Go)"

    ```go
    viper.Set("key", "value")         // override
    viper.SetDefault("key", "value")  // default
    ```

=== "Serum (Zig)"

    ```zig
    cfg.set("key", "value");         // override
    cfg.setDefault("key", "value");  // default
    ```

## Environment variables

=== "Viper (Go)"

    ```go
    viper.SetEnvPrefix("MYAPP")
    viper.AutomaticEnv()
    viper.BindEnv("database.password", "DB_PASSWORD")
    ```

=== "Serum (Zig)"

    ```zig
    cfg.setEnvPrefix("MYAPP");
    cfg.automaticEnv();
    cfg.bindEnv("database.password", "DB_PASSWORD");
    ```

## Key differences

| Aspect | Viper | Serum |
|--------|-------|-------|
| Memory | Heap-allocated maps | Fixed-size stack buffers |
| File reading | `ReadInConfig()` finds + reads | `readConfig(content)` — you read the file |
| Singleton | Global `viper.Get()` | Explicit `cfg.get()` instance |
| Value types | `interface{}` | `[]const u8` (parse with getInt/getBool) |
| Nested keys | `mapstructure` tags | Dot-delimited flat keys |
| Watch | `WatchConfig()` | Not implemented |
| Remote config | etcd, consul | Not implemented |
| All values stored as | `interface{}` | `[]const u8` (strings) |

## What's different

**No global singleton.** Viper has a global `viper.Get()`. Serum requires an explicit `Config` instance. This makes testing easier and avoids hidden state.

**All values are strings.** Viper stores typed values internally. Serum stores everything as `[]const u8` and parses on read (`getInt`, `getBool`). This simplifies the implementation and matches how config files and env vars work in practice.

**You read the file.** Viper has `ReadInConfig()` that searches paths and reads the file. Serum's `readConfig()` takes content directly. Read the file yourself with `std.fs` and pass the content. This keeps serum dependency-free and testable.
