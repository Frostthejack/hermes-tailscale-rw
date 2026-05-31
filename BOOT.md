# Startup Checklist

1. Run `hermes cron list` and check if any scheduled jobs have `last_status` of `error` or `failed`.
2. If any failed, send a summary to Discord #general using the send_message tool. Include the job name, schedule, and last error.
3. Check if any jobs are paused that shouldn't be (compare against expected active jobs).
4. Check disk usage with `df -h` (Linux) or `powershell Get-PSDrive C` (Windows). If usage is above 85%, include a disk space warning.
5. If nothing needs attention, reply with only: [SILENT]
