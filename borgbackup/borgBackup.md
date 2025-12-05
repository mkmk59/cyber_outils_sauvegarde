               ┌──────────────────┐
               │     data-app     │
               │  écrit /var/data │
               └─────────┬────────┘
                         │ volume partagé (app_data)
                         ▼
               ┌──────────────────┐
               │   borg-client    │
               │  borg create     │
               │  borg prune      │
               └─────────┬────────┘
                   SSH    │   (port 22 interne)
                         ▼
               ┌──────────────────┐
               │   borg-server    │
               │ héberge /repo    │
               │ via SSH + borg   │
               └──────────────────┘
