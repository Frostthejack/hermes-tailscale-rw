On this Windows host (luned), Hermes logs are at ~/AppData/Local/hermes/logs/ (e.g., gateway.log, errors.log), NOT at ~/.hermes/logs/ which read_file cannot find. The ~ expansion in read_file resolves differently than in terminal bash. systemctl is not available; use `hermes gateway status` (Scheduled Task-based) to check gateway health.
§
Started work on kanban task t_db3c7b96 on 2026-05-30.