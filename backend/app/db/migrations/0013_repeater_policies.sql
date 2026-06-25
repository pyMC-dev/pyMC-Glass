CREATE TABLE IF NOT EXISTS repeater_policy_templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    policy_json TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_repeater_policy_templates_enabled
ON repeater_policy_templates(enabled);

CREATE TABLE IF NOT EXISTS repeater_policy_sync_status (
    repeater_id TEXT PRIMARY KEY,
    template_id TEXT NULL,
    command_id TEXT NULL,
    payload_hash TEXT NULL,
    status TEXT NOT NULL DEFAULT 'idle',
    error_message TEXT NULL,
    queued_at TIMESTAMP NULL,
    dispatched_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    updated_at TIMESTAMP NOT NULL,
    FOREIGN KEY (repeater_id) REFERENCES repeaters(id) ON DELETE CASCADE,
    FOREIGN KEY (template_id) REFERENCES repeater_policy_templates(id) ON DELETE SET NULL,
    FOREIGN KEY (command_id) REFERENCES command_queue(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_repeater_policy_sync_status_template_id
ON repeater_policy_sync_status(template_id);

CREATE INDEX IF NOT EXISTS ix_repeater_policy_sync_status_command_id
ON repeater_policy_sync_status(command_id);

CREATE INDEX IF NOT EXISTS ix_repeater_policy_sync_status_payload_hash
ON repeater_policy_sync_status(payload_hash);

CREATE INDEX IF NOT EXISTS ix_repeater_policy_sync_status_status
ON repeater_policy_sync_status(status);
