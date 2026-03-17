# Environment Variables

Serum supports two ways to read environment variables: explicit binding and automatic lookup.

## Explicit binding

Bind a config key to a specific environment variable:

```zig
cfg.bindEnv("database.password", "DB_PASSWORD");
```

Now `cfg.get("database.password")` returns the value of `$DB_PASSWORD`.

## Automatic env

Enable automatic lookup that derives env var names from config keys:

```zig
cfg.automaticEnv();
```

With automatic env, `cfg.get("database.host")` checks `$DATABASE_HOST`.

The derivation rule:
- Dots become underscores
- Letters are uppercased

| Config key | Env var |
|------------|---------|
| `host` | `HOST` |
| `database.host` | `DATABASE_HOST` |
| `app.log.level` | `APP_LOG_LEVEL` |

## Env prefix

Add a prefix to avoid collisions with other apps:

```zig
cfg.setEnvPrefix("MYAPP");
cfg.automaticEnv();
```

| Config key | Env var |
|------------|---------|
| `host` | `MYAPP_HOST` |
| `database.host` | `MYAPP_DATABASE_HOST` |

## Precedence

Environment variables sit at layer 3 in the precedence chain:

```
overrides > flags > ENV VARS > config file > defaults
```

An explicit `cfg.set()` or `cfg.setFlag()` always beats an env var. But an env var always beats a config file value.

## Example: 12-factor app

```zig
var cfg = serum.Config.init();

// Sensible defaults
cfg.setDefault("port", "3000");
cfg.setDefault("host", "0.0.0.0");
cfg.setDefault("log.level", "info");

// Read config file (if available)
cfg.readConfig(config_content);

// Environment overrides everything from config
cfg.setEnvPrefix("MYAPP");
cfg.automaticEnv();

// Now: MYAPP_PORT=8080 overrides both default and config file
const port = cfg.getInt("port") orelse 3000;
_ = port;
```

This follows the [12-factor app](https://12factor.net/config) principle: store config in the environment.
