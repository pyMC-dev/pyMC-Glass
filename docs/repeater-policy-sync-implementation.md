# Repeater handoff: Glass `policy_sync`

_Last checked against Repeater commit `c0d919c` (`rightup/pyMC_Repeater` `origin/dev`, fetched 2026-06-24)._

## Current status

openHop Glass can build, validate, store, and queue Repeater Policy Engine templates. Glass queues a normal `/inform` command with action `policy_sync`.

The current Repeater branch does **not** yet execute `policy_sync` in `repeater/data_acquisition/glass_handler.py`. As of `c0d919c`, `GlassHandler._execute_command_action()` supports:

- `restart_service`
- `send_advert`
- `set_mode`
- `set_inform_interval`
- `rotate_cert`
- `config_update`
- `transport_keys_sync`
- `set_radio`
- `run_diagnostic`
- `export_config`

So this document remains the implementation contract for adding `policy_sync` to Repeater.

## Glass command shape

Glass queues `policy_sync` from `backend/app/api/routes/repeater_policy.py`. The command is delivered in the next `/inform` response as:

```json
{
  "type": "command",
  "command_id": "<uuid>",
  "action": "policy_sync",
  "params": {
    "policy": {
      "enabled": true,
      "default_action": "allow",
      "rules": [],
      "objects": {
        "channel_hash_groups": {
          "blocked_channels": ["0x12"]
        },
        "pubkey_groups": {
          "trusted_relays": ["0xaabbccdd"]
        }
      }
    },
    "mode": "replace",
    "validate_only": false,
    "source": "openHop Glass",
    "template_id": "<optional-template-id>"
  }
}
```

Notes:

- `policy` is the direct Repeater `policy_engine` object, not the full `policy.yaml` wrapper.
- `mode` is `replace` or `patch`.
- `validate_only=true` means validate and report the result without writing `policy.yaml` or swapping runtime policy.
- `template_id` is present only when the command came from a stored Glass template.
- Glass computes and tracks its own payload hash in sync status; the current command payload does not include that hash.

## Repeater policy file shape

Repeater stores policy config as a wrapper document. The Glass policy object should be written under `policy_engine`:

```yaml
policy_engine:
  enabled: true
  default_action: allow
  rules: []
  objects: {}
groups:
  channel_hashes: []
  pubkeys: []
```

Keep using `policy.yaml`. Do not create a second `policy.json` or Glass-specific policy store.

## Required Repeater changes

Implement `policy_sync` in `repeater/data_acquisition/glass_handler.py` inside `GlassHandler._execute_command_action()`.

Suggested branch point:

```python
if action == "policy_sync":
    success, message, details = self._apply_policy_sync(params)
    return success, message, details
```

Add `_apply_policy_sync(params)` with this behavior:

1. Validate `params` is a dict.
2. Extract `policy = params.get("policy")` and require a dict.
3. Accept `mode` values:
   - `replace`: replace the existing `policy_engine` object with the Glass policy.
   - `patch`: merge provided fields into the existing `policy_engine` while preserving unspecified fields.
4. Accept `validate_only`:
   - construct `PolicyEngine(normalized_policy)` and return success/failure without writing or changing runtime when true.
5. Resolve the policy file path the same way Repeater `/api/policy` does.
6. Load the existing full policy document if present; otherwise start from the default wrapper.
7. Preserve existing `groups` from `policy.yaml` unless Glass later sends an explicit `groups` key.
8. Normalize the incoming policy with the same rules used by `/api/policy`.
9. Project policy `groups` into `policy_engine.objects` with the same `/api/policy` behavior.
10. Write the full wrapper document back to YAML:
    - `policy_engine: <normalized-policy>`
    - `groups: <existing-or-provided-groups>`
11. Apply runtime policy immediately:
    - `self.config["policy_engine"] = normalized_policy`
    - `self.config["policy_file_path"] = <resolved-policy-path>`
    - `self.daemon_instance.repeater_handler.policy_engine = PolicyEngine.from_runtime_config(self.config)` or equivalent to the current `/api/policy` runtime helper.
12. Return command details that Glass can display and store:

```json
{
  "policy_file": "/etc/pymc_repeater/policy.yaml",
  "mode": "replace",
  "validate_only": false,
  "rule_count": 3,
  "enabled": true,
  "default_action": "allow"
}
```

The path `/etc/pymc_repeater/policy.yaml` is still the current Repeater default path. Do not rename it only for branding.

## Reuse existing Repeater code

The newest Repeater branch already has the needed policy helpers in `repeater/web/api_endpoints.py`:

- `POLICY_GROUP_KINDS`
- `_normalize_policy_groups`
- `_write_policy_document`
- `_sync_policy_engine_objects_from_groups`
- `_get_policy_file_path`
- `_load_policy_document`
- `_normalize_policy_engine`
- `_apply_policy_runtime`

Best implementation options:

1. Refactor these helpers into a small shared policy service module and call it from both `APIEndpoints` and `GlassHandler`.
2. If a refactor is too large, copy the exact helper behavior into `GlassHandler` and add tests proving `/api/policy` and `policy_sync` write the same shape.

Do not diverge from `/api/policy`; Glass sync should produce the same `policy.yaml` and runtime state as a local Repeater API policy update.

## Compatibility details

Glass policy editor pre-stages object groups under:

- `objects.channel_hash_groups`
- `objects.pubkey_groups`

Repeater `PolicyEngine` currently supports object reference resolution with `@group.key` lookups from `policy_engine.objects`. It also supports channel secret/hash matching through `objects.channels` and `objects.channel_hash_groups`.

Keep field support aligned with `repeater/policy_engine.py`, including the currently supported condition fields:

- `payload_hex`
- `channel_message_body`
- `channel_sender`
- `channel_decryptable`
- `transport_code_0`
- `transport_code_1`

Also preserve existing context-backed fields used by the policy engine, such as packet metadata passed through `policy_context`.

## Command result contract

Repeater should report completion on the next `/inform` with Glass' existing command result shape:

```json
{
  "command_id": "<uuid>",
  "status": "success",
  "message": "Policy synchronized",
  "completed_at": "2026-06-24T12:00:00Z",
  "details": {
    "policy_file": "/etc/pymc_repeater/policy.yaml",
    "mode": "replace",
    "validate_only": false,
    "rule_count": 3,
    "enabled": true,
    "default_action": "allow"
  }
}
```

Valid statuses are `success`, `failed`, and `partial`.

## Tests to add in Repeater

Add focused tests in Repeater around `GlassHandler._execute_command_action("policy_sync", params)` and any shared helper module:

1. `validate_only=true` validates but does not write `policy.yaml` and does not replace runtime policy.
2. `replace` writes a full wrapper document with `policy_engine` and preserved `groups`.
3. `patch` preserves existing `policy_engine.objects`, rules, and unspecified fields unless explicitly overwritten.
4. Policy `groups` are projected into `policy_engine.objects` the same way `/api/policy` does.
5. Runtime handler receives a new `PolicyEngine` instance after a successful non-validate sync.
6. Invalid policy returns `success=False` and a useful message.
7. Unsupported `mode` returns `success=False`.

## Acceptance check

After Repeater implementation:

1. Create or select a Repeater Runtime Policy template in Glass.
2. Add a policy group and a rule that references it, e.g. `@channel_hash_groups.blocked_channels`.
3. Queue `policy_sync` to a Repeater running the current branch.
4. Confirm the next Repeater `/inform` receives `action="policy_sync"`.
5. Confirm Repeater reports command result `success` on a following `/inform`.
6. Confirm Repeater `policy.yaml` contains the policy under `policy_engine` with preserved/merged `groups`.
7. Confirm Repeater runtime policy behavior changes without requiring a service restart.
8. Confirm Glass sync status transitions from `queued`/`dispatched` to completed.
