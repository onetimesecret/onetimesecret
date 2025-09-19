# Enabling Redis DEBUG POPULATE Command

To enable the ```DEBUG POPULATE``` command, you need to modify your Redis configuration:

## Method 1: Configuration File
Edit your ```redis.conf``` file and add:

```conf
enable-debug-command yes
```

Then restart Redis:
```bash
sudo systemctl restart redis
# or
redis-server /path/to/redis.conf
```

## Method 2: Runtime Configuration
Enable it temporarily without restart:

```bash
redis-cli CONFIG SET enable-debug-command yes
```

## Method 3: Local Connection Only
For security, you can enable DEBUG commands only for local connections:

```conf
enable-debug-command local
```

This allows DEBUG commands only when connecting from localhost (127.0.0.1).

## Using DEBUG POPULATE After Enabling
Once enabled, you can use:

```bash
# Generate 1000 keys with default prefix and size
redis-cli DEBUG POPULATE 1000

# Generate with custom prefix and value size (bytes)
redis-cli DEBUG POPULATE 1000 "mykey:" 100
```

## Security Note
The DEBUG command is disabled by default for security reasons as it's meant for development and testing. [^2] In production environments, consider using the "local" option or the alternative methods mentioned earlier (redis-benchmark, Lua scripts) instead of permanently enabling DEBUG commands. [^1]

After enabling, your original command ```redis-cli DEBUG POPULATE 2``` should work successfully.

[^1]: [Debugging | Docs - Redis](https://redis.io/docs/latest/operate/oss_and_stack/management/debugging/#:~:text=Redis%20has,real%20production) 64%
[^2]: [DEBUG | Docs - Redis](https://redis.io/docs/latest/commands/debug/#:~:text=The%20DEBUG,testing%20Redis.) 36%
