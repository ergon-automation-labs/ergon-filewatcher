# Bot Army Filewatcher

Monitors filesystem changes and git status for the Bot Army ecosystem.

## Features

- **Git Status Monitoring** - Tracks untracked files, staged changes, dirty repos
- **Dirty Repo Detection** - Warns when >10 untracked files, suggests cleanup
- **Test Suggestions** - Offers to run tests when relevant files change
- **Context Signals** - Publishes signals to context broker for mode changes

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FILEWATCHER_WATCHED_DIRS` | Empty | Comma-separated list of directories to watch |
| `FILEWATCHER_GIT_THRESHOLD` | `10` | Untracked file count before warning |
| `FILEWATCHER_WATCH_INTERVAL` | `1000` | Watch loop interval in milliseconds |

### Example: Docker Compose

```yaml
filewatcher:
  image: filewatcher_bot
  environment:
    FILEWATCHER_WATCHED_DIRS: "/app/bots/bot_army_gtd,/app/bots/bot_army_context_broker"
    FILEWATCHER_GIT_THRESHOLD: "10"
  volumes:
    - ./bots:/app/bots
```

### Example: Salt State (bot_army_infra)

```yaml
filewatcher_env:
  file.line:
    - name: /etc/environment
    - match: 'FILEWATCHER_WATCHED_DIRS'
    - content: 'FILEWATCHER_WATCHED_DIRS=/opt/bots/bot_army_gtd,/opt/bots/bot_army_context_broker'
```

### Example: Development

```bash
export FILEWATCHER_WATCHED_DIRS="/Users/abby/code/bots/bot_army_gtd,/Users/abby/code/bots/bot_army_context_broker"
export FILEWATCHER_GIT_THRESHOLD=10
mix phx.server
```

## NATS Subjects

### Subscribes
None - Filewatcher is an active watcher, not a subscriber.

### Publishes
- `context.signal.filewatcher` - File/directory change signals
- `events.filewatcher.git_status` - Git status snapshots
- `events.filewatcher.dirty_repo_warning` - Dirty repo warnings
- `events.filewatcher.test_suggestion` - Test suggestion events

### Query API
- `filewatcher.status.query` - Get current filewatcher status
- `filewatcher.git_status.query` - Get git status for a directory

#### Query Payload
```json
{
  "directory": "/path/to/repo"
}
```

#### Response
```json
{
  "ok": true,
  "schema_version": "1.0",
  "timestamp": "2026-06-01T...",
  "directory": "/path/to/repo",
  "status": {
    "untracked": 5,
    "staged": 2,
    "unstaged": 1,
    "total": 8
  }
}
```
