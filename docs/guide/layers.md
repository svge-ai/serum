# Configuration Layers

Serum uses a layered configuration model where each layer shadows the ones below it. This is the same precedence model as viper.

## Precedence order

| Priority | Layer | Set via | Use case |
|----------|-------|---------|----------|
| 1 (highest) | Overrides | `cfg.set(key, value)` | Runtime overrides, test fixtures |
| 2 | Flags | `cfg.setFlag(key, value)` | CLI flag values from mamba |
| 3 | Environment | `MYAPP_KEY=value` | 12-factor app config, secrets |
| 4 | Config file | `cfg.readConfig(content)` | YAML/TOML config files |
| 5 (lowest) | Defaults | `cfg.setDefault(key, value)` | Sensible fallbacks |

## How lookup works

When you call `cfg.get("port")`, serum checks each layer in order:

1. Is `"port"` in overrides? If yes, return it.
2. Is `"port"` in flags? If yes, return it.
3. Is `"port"` bound to an env var? Is that env var set? If yes, return it.
4. Is `"port"` in the config file? If yes, return it.
5. Is `"port"` in defaults? If yes, return it.
6. Return `null`.

This means an environment variable always beats a config file value, and a CLI flag always beats an environment variable.

## Example: all layers active

```zig
var cfg = serum.Config.init();

// Defaults
cfg.setDefault("port", "3000");

// Config file (overrides default)
cfg.readConfig("port: 8080\n");

// Env var (overrides config file)
cfg.bindEnv("port", "PORT");
// If PORT=9090 is set in environment:

// Flag (overrides env var)
cfg.setFlag("port", "4000");

// Override (overrides everything)
cfg.set("port", "5000");

cfg.getString("port");  // "5000"
```

Remove the override:

```zig
// Without cfg.set(), the flag layer wins:
cfg.getString("port");  // "4000"
```

## Why layered?

This model lets you:

- Ship sensible defaults in code
- Let users customize via config file
- Let deployment override via env vars (12-factor)
- Let CLI flags override everything for one-off runs
- Let test code override anything via `set()`
