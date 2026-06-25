<template>
  <div class="space-y-5">
    <header class="page-header">
      <div>
        <h1 class="section-title">Repeater Runtime Policy</h1>
        <p class="section-subtitle">
          Build repeater Policy Engine templates with a form editor, validate them, and queue policy_sync to repeaters.
        </p>
      </div>
      <div class="header-actions">
        <button class="btn btn-secondary" :disabled="loading" @click="loadAll">Refresh</button>
        <button class="btn btn-primary" :disabled="!canOperate" @click="startNewTemplate">New template</button>
      </div>
    </header>

    <section class="grid-2">
      <UiPanelCard title="Policy Templates" subtitle="Saved Glass-side repeater Policy Engine documents.">
        <div v-if="templates.length === 0" class="empty-state">No repeater policy templates yet.</div>
        <div v-else class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Status</th>
                <th>Rules</th>
                <th>Updated</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="template in templates"
                :key="template.id"
                class="clickable-row"
                :class="{ selected: selectedTemplate?.id === template.id }"
                @click="selectTemplate(template)"
              >
                <td>
                  <strong>{{ template.name }}</strong>
                  <span class="muted-block">{{ template.description || "No description" }}</span>
                </td>
                <td><StatusPill :status="template.enabled ? 'enabled' : 'disabled'" /></td>
                <td>{{ ruleCount(template.policy) }}</td>
                <td>{{ formatTimestamp(template.updated_at) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </UiPanelCard>

      <UiPanelCard title="Template Details" subtitle="Name the policy template and choose how it appears in Glass.">
        <form class="panel-form" @submit.prevent="saveTemplate">
          <label class="field-label">
            Template name
            <input v-model.trim="form.name" class="field" required />
          </label>
          <label class="field-label">
            Description
            <input v-model.trim="form.description" class="field" />
          </label>
          <label class="toggle-row">
            <input v-model="form.enabled" type="checkbox" />
            <span>Template enabled</span>
          </label>

          <div class="settings-actions">
            <button class="btn btn-secondary" type="button" :disabled="loading" @click="validateCurrentPolicy">
              Validate
            </button>
            <button class="btn btn-primary" :disabled="loading || !canOperate">
              {{ selectedTemplate ? "Save template" : "Create template" }}
            </button>
            <button
              v-if="selectedTemplate"
              class="btn btn-danger"
              type="button"
              :disabled="loading || !canOperate"
              @click="deleteSelectedTemplate"
            >
              Delete
            </button>
          </div>
          <div v-if="validation" class="section-subtitle" :class="validation.valid ? 'text-emerald-300' : 'text-rose-300'">
            {{ validation.valid ? "Policy is valid." : validation.errors.join("; ") }}
          </div>
        </form>
      </UiPanelCard>

      <UiPanelCard title="Example Templates" subtitle="Start from common repeater alert/policy patterns, then customize before saving.">
        <div class="example-template-list">
          <button
            v-for="example in EXAMPLE_POLICIES"
            :key="example.name"
            class="btn btn-secondary"
            type="button"
            @click="applyExamplePolicy(example)"
          >
            {{ example.name }}
          </button>
        </div>
      </UiPanelCard>
    </section>

    <UiPanelCard title="Policy Engine Editor" subtitle="Form editor for the repeater policy_engine object. JSON mode is still available for advanced fields.">
      <div class="editor-mode-row">
        <button
          class="btn"
          :class="editorMode === 'builder' ? 'btn-primary' : 'btn-secondary'"
          type="button"
          @click="switchEditorMode('builder')"
        >
          Visual editor
        </button>
        <button
          class="btn"
          :class="editorMode === 'json' ? 'btn-primary' : 'btn-secondary'"
          type="button"
          @click="switchEditorMode('json')"
        >
          JSON editor
        </button>
      </div>

      <div v-if="editorMode === 'builder'" class="policy-builder">
        <section class="policy-builder-section tab-section">
          <div class="editor-mode-row builder-tab-row">
            <button
              class="btn"
              :class="builderTab === 'policy' ? 'btn-primary' : 'btn-secondary'"
              type="button"
              @click="builderTab = 'policy'"
            >
              Policy
            </button>
            <button
              class="btn"
              :class="builderTab === 'objects' ? 'btn-primary' : 'btn-secondary'"
              type="button"
              @click="builderTab = 'objects'"
            >
              Objects
            </button>
          </div>
        </section>

        <template v-if="builderTab === 'policy'">
        <section class="policy-builder-section">
          <div class="grid-2">
            <label class="toggle-row builder-toggle">
              <input v-model="builder.enabled" type="checkbox" @change="syncJsonFromBuilder" />
              <span>Policy Engine enabled</span>
            </label>
            <label class="field-label">
              Default action when no rule matches
              <select v-model="builder.defaultAction" class="field" @change="syncJsonFromBuilder">
                <option value="allow">allow</option>
                <option value="drop">drop</option>
                <option value="log_only">log_only</option>
              </select>
            </label>
          </div>
        </section>

        <section class="policy-builder-section">
          <div class="policy-section-header">
            <div>
              <h3 class="policy-section-title">Add Policy Rule</h3>
              <p class="section-subtitle">Choose match logic, then add one or more conditions. ALL conditions must match.</p>
            </div>
            <button class="btn btn-secondary" type="button" @click="addRule">Add Policy Rule</button>
          </div>

          <div v-if="builder.rules.length === 0" class="empty-state">No rules. Default action will apply.</div>
          <article v-for="(rule, ruleIndex) in builder.rules" :key="rule.localId" class="rule-card repeater-style-rule">
            <div class="repeater-rule-grid">
              <label class="field-label">
                Rule Name
                <input v-model.trim="rule.name" class="field" @input="syncJsonFromBuilder" />
              </label>
              <label class="field-label">
                Match Logic
                <select v-model="rule.logic" class="field" @change="syncJsonFromBuilder">
                  <option value="all">ALL</option>
                  <option value="any">ANY</option>
                </select>
              </label>
              <label class="field-label">
                Action
                <select v-model="rule.action" class="field" @change="syncJsonFromBuilder">
                  <option value="allow">allow</option>
                  <option value="drop">drop</option>
                  <option value="log_only">log_only</option>
                </select>
              </label>
              <label class="toggle-row builder-toggle">
                <input v-model="rule.enabled" type="checkbox" @change="syncJsonFromBuilder" />
                <span>Rule enabled</span>
              </label>
            </div>

            <div class="condition-list repeater-conditions">
              <div class="policy-section-header compact-header">
                <h4 class="condition-title">Conditions</h4>
                <div class="rule-actions">
                  <button class="btn btn-secondary" type="button" @click="addCondition(ruleIndex)">Add condition</button>
                  <button class="btn btn-danger" type="button" @click="removeRule(ruleIndex)">Remove rule</button>
                </div>
              </div>
              <div v-if="rule.conditions.length === 0" class="empty-state small">Add at least one condition for this rule to match.</div>
              <div v-else class="conditions-table-wrap">
                <table class="table conditions-table">
                  <thead>
                    <tr>
                      <th>Drag</th>
                      <th>Field</th>
                      <th>Operator</th>
                      <th>Source</th>
                      <th>Value</th>
                      <th>Type</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="(condition, conditionIndex) in rule.conditions" :key="condition.localId">
                      <td class="drag-cell">
                        <button class="mini-btn" type="button" :disabled="conditionIndex === 0" @click="moveCondition(ruleIndex, conditionIndex, -1)">↑</button>
                        <button class="mini-btn" type="button" :disabled="conditionIndex === rule.conditions.length - 1" @click="moveCondition(ruleIndex, conditionIndex, 1)">↓</button>
                      </td>
                      <td>
                        <select v-model="condition.field" class="field table-field" @change="syncJsonFromBuilder">
                          <option v-for="field in fieldOptions" :key="field.value" :value="field.value">{{ field.label }}</option>
                        </select>
                      </td>
                      <td>
                        <select v-model="condition.op" class="field table-field" @change="syncJsonFromBuilder">
                          <option v-for="op in operatorOptions" :key="op.value" :value="op.value">{{ op.label }}</option>
                        </select>
                      </td>
                      <td>
                        <select v-model="condition.valueSource" class="field table-field" @change="onConditionValueSourceChange(condition)">
                          <option value="literal">Literal</option>
                          <option value="group">Group</option>
                        </select>
                      </td>
                      <td>
                        <div v-if="condition.valueSource === 'group'" class="group-ref-controls">
                          <select
                            v-model="condition.groupKind"
                            class="field table-field"
                            @change="onConditionGroupKindChange(condition)"
                          >
                            <option value="channel_hash_groups">Channel hash group</option>
                            <option value="pubkey_groups">Pubkey group</option>
                          </select>
                          <select
                            v-model="condition.groupId"
                            class="field table-field"
                            @change="syncJsonFromBuilder"
                          >
                            <option value="">Select group</option>
                            <option v-for="name in groupNamesForKind(condition.groupKind)" :key="name" :value="name">{{ name }}</option>
                          </select>
                        </div>
                        <input
                          v-else
                          v-model="condition.value"
                          class="field table-field value-field"
                          placeholder="value"
                          @input="syncJsonFromBuilder"
                        />
                      </td>
                      <td>
                        <select v-model="condition.valueType" class="field table-field" @change="syncJsonFromBuilder">
                          <option value="string">String</option>
                          <option value="number">Number</option>
                          <option value="boolean">Boolean</option>
                        </select>
                      </td>
                      <td>
                        <button class="btn btn-danger condition-remove" type="button" @click="removeCondition(ruleIndex, conditionIndex)">
                          Remove
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </article>
        </section>

        </template>

        <template v-else>
        <section class="policy-builder-section">
          <div class="policy-section-header">
            <div>
              <h3 class="policy-section-title">Objects</h3>
              <p class="section-subtitle">Named groups referenced from condition values, e.g. <code>@channel_hash_groups.blocked</code>.</p>
            </div>
          </div>
          <textarea v-model="builder.objectsJson" class="field-textarea objects-json" spellcheck="false" @input="syncJsonFromBuilder" />
        </section>

        <section class="policy-builder-section">
          <div class="policy-section-header">
            <div>
              <h3 class="policy-section-title">Policy Groups</h3>
              <p class="section-subtitle">Pre-stage Repeater policy groups; these update the policy objects JSON used by group references.</p>
            </div>
          </div>
          <div class="grid-2">
            <label class="field-label">
              Group kind
              <select v-model="groupForm.kind" class="field">
                <option value="channel_hash_groups">Channel hash groups</option>
                <option value="pubkey_groups">Pubkey groups</option>
              </select>
            </label>
            <label class="field-label">
              Group name
              <input v-model.trim="groupForm.name" class="field" placeholder="blocked_channels" />
            </label>
          </div>
          <div class="settings-actions">
            <button class="btn btn-secondary" type="button" @click="addObjectGroup">Add group</button>
            <button class="btn btn-danger" type="button" :disabled="!selectedObjectGroupName" @click="removeObjectGroup(selectedObjectGroupName)">Remove selected group</button>
          </div>
          <div v-if="objectGroupNames.length === 0" class="empty-state small">No {{ groupKindLabel(groupForm.kind) }} yet.</div>
          <div v-else class="policy-group-list">
            <button
              v-for="name in objectGroupNames"
              :key="name"
              class="policy-group-chip"
              :class="{ selected: selectedObjectGroupName === name }"
              type="button"
              @click="groupForm.name = name"
            >
              {{ name }} <span>{{ selectedObjectGroupValues(name).length }}</span>
            </button>
          </div>
          <div class="grid-2">
            <label class="field-label">
              Entry value
              <input v-model.trim="groupForm.entryValue" class="field" :placeholder="groupForm.kind === 'channel_hash_groups' ? '0x12 or 0x9CD8…' : '0xaabbccdd'" />
            </label>
            <div class="field-label group-entry-actions">
              Add entry
              <button class="btn btn-secondary" type="button" :disabled="!selectedObjectGroupName" @click="addObjectGroupEntry">Add to selected group</button>
            </div>
          </div>
          <div v-if="selectedObjectGroupName" class="policy-group-entry-list">
            <span v-for="entry in selectedObjectGroupValues(selectedObjectGroupName)" :key="entry" class="entry-pill">
              {{ entry }}
              <button type="button" @click="removeObjectGroupEntry(selectedObjectGroupName, entry)">×</button>
            </span>
          </div>
        </section>
        </template>
      </div>

      <div v-else>
        <label class="field-label">
          Policy Engine JSON
          <textarea v-model="form.policyJson" class="field-textarea policy-json" spellcheck="false" @blur="loadBuilderFromJson" />
        </label>
      </div>
    </UiPanelCard>

    <UiPanelCard title="Queue policy_sync" subtitle="Queues policy_sync commands; repeaters need policy_sync support before execution succeeds.">
      <div class="grid-2">
        <label class="field-label">
          Target template
          <select v-model="syncForm.templateId" class="field">
            <option value="">Use editor policy</option>
            <option v-for="template in templates" :key="template.id" :value="template.id">
              {{ template.name }}
            </option>
          </select>
        </label>
        <label class="field-label">
          Mode
          <select v-model="syncForm.mode" class="field">
            <option value="replace">replace</option>
            <option value="patch">patch</option>
          </select>
        </label>
      </div>
      <label class="toggle-row">
        <input v-model="syncForm.allRepeaters" type="checkbox" />
        <span>Queue to all eligible repeaters</span>
      </label>
      <label class="toggle-row">
        <input v-model="syncForm.validateOnly" type="checkbox" />
        <span>Validate-only command</span>
      </label>
      <div v-if="!syncForm.allRepeaters" class="checkbox-grid">
        <label v-for="repeater in appState.repeaters" :key="repeater.id" class="toggle-row compact">
          <input v-model="syncForm.repeaterIds" type="checkbox" :value="repeater.id" />
          <span>{{ repeater.node_name }} <small class="text-slate-500">({{ repeater.status }})</small></span>
        </label>
      </div>
      <label class="field-label">
        Reason
        <input v-model.trim="syncForm.reason" class="field" placeholder="e.g. initial packet policy rollout" />
      </label>
      <div class="settings-actions">
        <button class="btn btn-danger" :disabled="loading || !canOperate" @click="queueSync">Queue policy_sync</button>
      </div>
    </UiPanelCard>

    <UiPanelCard title="Sync Status" subtitle="Latest policy sync state per repeater.">
      <div v-if="syncStatuses.length === 0" class="empty-state">No policy sync commands queued yet.</div>
      <div v-else class="table-wrap">
        <table class="table sync-status-table">
          <thead>
            <tr>
              <th>Repeater</th>
              <th>Status</th>
              <th>Command</th>
              <th>Last update</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="status in syncStatuses" :key="status.repeater_id">
              <td>
                <strong>{{ status.node_name }}</strong>
                <span v-if="status.error_message" class="muted-block text-rose-300">{{ status.error_message }}</span>
              </td>
              <td><StatusPill :status="status.status" /></td>
              <td>
                <code v-if="status.command_id" class="command-id" :title="status.command_id">
                  {{ formatCommandId(status.command_id) }}
                </code>
                <span v-else>—</span>
              </td>
              <td class="nowrap-cell">{{ formatTimestamp(status.updated_at) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </UiPanelCard>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";

import {
  createRepeaterPolicyTemplate,
  deleteRepeaterPolicyTemplate,
  listRepeaterPolicySyncStatus,
  listRepeaterPolicyTemplates,
  syncRepeaterPolicy,
  updateRepeaterPolicyTemplate,
  validateRepeaterPolicy,
} from "../api";
import UiPanelCard from "../components/ui/UiPanelCard.vue";
import StatusPill from "../components/ui/StatusPill.vue";
import { appState, canOperate, formatTimestamp, showErrorToast, showSuccessToast } from "../state/appState";
import type {
  RepeaterPolicySyncStatusResponse,
  RepeaterPolicyTemplateResponse,
  RepeaterPolicyValidateResponse,
} from "../types";

type Action = "allow" | "drop" | "log_only";
type Logic = "all" | "any";
type EditorMode = "builder" | "json";
type BuilderTab = "policy" | "objects";
type RuleValueType = "string" | "number" | "boolean";
type ValueSource = "literal" | "group";
type PolicyObjectGroupKind = "channel_hash_groups" | "pubkey_groups";

type BuilderCondition = {
  localId: string;
  field: string;
  op: string;
  value: string;
  valueType: RuleValueType;
  valueSource: ValueSource;
  groupKind?: PolicyObjectGroupKind;
  groupId?: string;
};

type BuilderRule = {
  localId: string;
  id: string;
  name: string;
  enabled: boolean;
  logic: Logic;
  action: Action;
  conditions: BuilderCondition[];
};

const DEFAULT_POLICY = {
  enabled: true,
  default_action: "allow",
  rules: [],
  objects: {
    channel_hash_groups: {},
    pubkey_groups: {},
  },
};

const EXAMPLE_POLICIES = [
  {
    name: "Log High Airtime",
    description: "Log packets when airtime/utilization is high so operators can tune busy links.",
    policy: {
      enabled: true,
      default_action: "allow",
      rules: [
        {
          id: "log-high-airtime",
          name: "Log high airtime",
          enabled: true,
          if: {
            any: [
              { field: "airtime_percent", op: "greater_or_equal", value: 80 },
              { field: "utilization_percent", op: "greater_or_equal", value: 80 },
            ],
          },
          then: { action: "log_only" },
        },
      ],
      objects: {
        channel_hash_groups: {},
        pubkey_groups: {},
      },
    },
  },
  {
    name: "Drop Noisy Low Signal",
    description: "Drop packets with very weak RSSI and low SNR while allowing normal traffic.",
    policy: {
      enabled: true,
      default_action: "allow",
      rules: [
        {
          id: "drop-noisy-low-signal",
          name: "Drop noisy low signal",
          enabled: true,
          if: {
            all: [
              { field: "rssi", op: "less_or_equal", value: -120 },
              { field: "snr", op: "less_or_equal", value: -12 },
            ],
          },
          then: { action: "drop" },
        },
      ],
      objects: {
        channel_hash_groups: {},
        pubkey_groups: {},
      },
    },
  },
  {
    name: "Allow Known Pubkey Group",
    description: "Example group-backed allow list for trusted node public keys.",
    policy: {
      enabled: true,
      default_action: "log_only",
      rules: [
        {
          id: "allow-known-pubkeys",
          name: "Allow known pubkeys",
          enabled: true,
          if: {
            any: [
              { field: "sender_pubkey", op: "in", value: "@pubkey_groups.trusted_nodes" },
              { field: "author_pubkey", op: "in", value: "@pubkey_groups.trusted_nodes" },
            ],
          },
          then: { action: "allow" },
        },
      ],
      objects: {
        channel_hash_groups: {},
        pubkey_groups: {
          trusted_nodes: ["replace-with-node-public-key"],
        },
      },
    },
  },
];

const fieldOptions = [
  { value: "route_type", label: "Route Type" },
  { value: "payload_type", label: "Payload Type" },
  { value: "payload_length", label: "Payload Length" },
  { value: "path_hash_size", label: "Path Hash Size" },
  { value: "hop_count", label: "Hop Count" },
  { value: "rssi", label: "RSSI" },
  { value: "snr", label: "SNR" },
  { value: "airtime_percent", label: "Airtime Percent" },
  { value: "utilization_percent", label: "Utilization Percent" },
  { value: "sender_pubkey", label: "Sender Pubkey" },
  { value: "author_pubkey", label: "Author Pubkey" },
  { value: "mode", label: "Mode" },
  { value: "local_transmission", label: "Local Transmission" },
  { value: "path_hashes", label: "Path Hashes" },
  { value: "channel_hash", label: "Channel Hash" },
  { value: "channel_decryptable", label: "Channel Decryptable" },
  { value: "channel_message_body", label: "Channel Message Body" },
  { value: "channel_sender", label: "Channel Sender" },
  { value: "payload_hex", label: "Payload Hex" },
  { value: "transport_code_0", label: "Transport Code 0" },
  { value: "transport_code_1", label: "Transport Code 1" },
];

const operatorOptions = [
  { value: "equals", label: "Equals" },
  { value: "not_equals", label: "Not Equals" },
  { value: "greater_than", label: "Greater Than" },
  { value: "greater_or_equal", label: "Greater or Equal" },
  { value: "less_than", label: "Less Than" },
  { value: "less_or_equal", label: "Less or Equal" },
  { value: "contains", label: "Contains" },
  { value: "in", label: "In List" },
  { value: "intersects", label: "Intersects" },
  { value: "starts_with", label: "Starts With" },
  { value: "ends_with", label: "Ends With" },
];

const loading = ref(false);
const templates = ref<RepeaterPolicyTemplateResponse[]>([]);
const syncStatuses = ref<RepeaterPolicySyncStatusResponse[]>([]);
const selectedTemplate = ref<RepeaterPolicyTemplateResponse | null>(null);
const validation = ref<RepeaterPolicyValidateResponse | null>(null);
const editorMode = ref<EditorMode>("builder");
const builderTab = ref<BuilderTab>("policy");

const form = reactive({
  name: "",
  description: "",
  enabled: true,
  policyJson: JSON.stringify(DEFAULT_POLICY, null, 2),
});

const builder = reactive({
  enabled: true,
  defaultAction: "allow" as Action,
  objectsJson: JSON.stringify(DEFAULT_POLICY.objects, null, 2),
  rules: [] as BuilderRule[],
});

const syncForm = reactive({
  templateId: "",
  allRepeaters: true,
  repeaterIds: [] as string[],
  mode: "replace" as "replace" | "patch",
  validateOnly: false,
  reason: "",
});

const groupForm = reactive({
  kind: "channel_hash_groups" as PolicyObjectGroupKind,
  name: "",
  entryValue: "",
});

const policyObjects = computed<Record<string, unknown>>(() => parseObjectsJson());

const objectGroupNames = computed(() => {
  const groups = objectGroupsForKind(groupForm.kind);
  return Object.keys(groups).sort((a, b) => a.localeCompare(b));
});

const selectedObjectGroupName = computed(() => {
  const name = groupForm.name.trim();
  return name && Object.prototype.hasOwnProperty.call(objectGroupsForKind(groupForm.kind), name) ? name : "";
});

onMounted(() => {
  loadBuilderFromJson({ silent: true });
  void loadAll();
});

async function loadAll(): Promise<void> {
  if (!appState.token) return;
  loading.value = true;
  try {
    const [templateRows, statusRows] = await Promise.all([
      listRepeaterPolicyTemplates(appState.token),
      listRepeaterPolicySyncStatus(appState.token),
    ]);
    templates.value = templateRows;
    syncStatuses.value = statusRows;
  } catch (error) {
    showErrorToast(error instanceof Error ? error.message : "Failed to load repeater policies");
  } finally {
    loading.value = false;
  }
}

function startNewTemplate(): void {
  selectedTemplate.value = null;
  form.name = "";
  form.description = "";
  form.enabled = true;
  form.policyJson = JSON.stringify(DEFAULT_POLICY, null, 2);
  syncForm.templateId = "";
  validation.value = null;
  loadBuilderFromJson({ silent: true });
}

function selectTemplate(template: RepeaterPolicyTemplateResponse): void {
  selectedTemplate.value = template;
  form.name = template.name;
  form.description = template.description || "";
  form.enabled = template.enabled;
  form.policyJson = JSON.stringify(template.policy, null, 2);
  syncForm.templateId = template.id;
  validation.value = null;
  loadBuilderFromJson({ silent: true });
}

function applyExamplePolicy(example: (typeof EXAMPLE_POLICIES)[number]): void {
  selectedTemplate.value = null;
  form.name = example.name;
  form.description = example.description;
  form.enabled = true;
  form.policyJson = JSON.stringify(example.policy, null, 2);
  syncForm.templateId = "";
  validation.value = null;
  editorMode.value = "builder";
  loadBuilderFromJson({ silent: true });
  showSuccessToast(`Loaded example template: ${example.name}`);
}

function switchEditorMode(mode: EditorMode): void {
  if (mode === editorMode.value) return;
  if (mode === "builder") {
    loadBuilderFromJson();
  } else {
    syncJsonFromBuilder();
  }
  editorMode.value = mode;
}

function parsePolicy(): Record<string, unknown> | null {
  if (editorMode.value === "builder") {
    const policy = policyFromBuilder();
    if (!policy) return null;
    form.policyJson = JSON.stringify(policy, null, 2);
    return policy;
  }

  try {
    const parsed = JSON.parse(form.policyJson);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      showErrorToast("Policy JSON must be an object.");
      return null;
    }
    return unwrapPolicyEngine(parsed as Record<string, unknown>);
  } catch (error) {
    showErrorToast(error instanceof Error ? error.message : "Policy JSON is invalid.");
    return null;
  }
}

async function validateCurrentPolicy(): Promise<boolean> {
  if (!appState.token) return false;
  const policy = parsePolicy();
  if (!policy) return false;
  try {
    validation.value = await validateRepeaterPolicy(appState.token, { policy });
    if (!validation.value.valid) {
      showErrorToast(validation.value.errors.join("; "));
      return false;
    }
    showSuccessToast("Repeater policy is valid.");
    return true;
  } catch (error) {
    showErrorToast(error instanceof Error ? error.message : "Policy validation failed");
    return false;
  }
}

async function saveTemplate(): Promise<void> {
  if (!appState.token) return;
  const policy = parsePolicy();
  if (!policy) return;
  loading.value = true;
  try {
    if (selectedTemplate.value) {
      const updated = await updateRepeaterPolicyTemplate(appState.token, selectedTemplate.value.id, {
        name: form.name,
        description: form.description || null,
        enabled: form.enabled,
        policy,
      });
      selectedTemplate.value = updated;
      showSuccessToast("Repeater policy template saved.");
    } else {
      const created = await createRepeaterPolicyTemplate(appState.token, {
        name: form.name,
        description: form.description || null,
        enabled: form.enabled,
        policy,
      });
      selectedTemplate.value = created;
      syncForm.templateId = created.id;
      showSuccessToast("Repeater policy template created.");
    }
    await loadAll();
  } catch (error) {
    showErrorToast(error instanceof Error ? error.message : "Failed to save repeater policy template");
  } finally {
    loading.value = false;
  }
}

async function deleteSelectedTemplate(): Promise<void> {
  if (!appState.token || !selectedTemplate.value) return;
  loading.value = true;
  try {
    await deleteRepeaterPolicyTemplate(appState.token, selectedTemplate.value.id);
    showSuccessToast("Repeater policy template deleted.");
    startNewTemplate();
    await loadAll();
  } catch (error) {
    showErrorToast(error instanceof Error ? error.message : "Failed to delete repeater policy template");
  } finally {
    loading.value = false;
  }
}

async function queueSync(): Promise<void> {
  if (!appState.token) return;
  const policy = syncForm.templateId ? undefined : parsePolicy();
  if (!syncForm.templateId && !policy) return;
  loading.value = true;
  try {
    const result = await syncRepeaterPolicy(appState.token, {
      template_id: syncForm.templateId || undefined,
      policy,
      all_repeaters: syncForm.allRepeaters,
      repeater_ids: syncForm.allRepeaters ? [] : syncForm.repeaterIds,
      mode: syncForm.mode,
      validate_only: syncForm.validateOnly,
      reason: syncForm.reason || undefined,
    });
    showSuccessToast(`Queued ${result.queued_commands} policy_sync command${result.queued_commands === 1 ? "" : "s"}.`);
    await loadAll();
  } catch (error) {
    showErrorToast(error instanceof Error ? error.message : "Failed to queue policy sync");
  } finally {
    loading.value = false;
  }
}

function addRule(): void {
  const nextNumber = builder.rules.length + 1;
  builder.rules.push({
    localId: newLocalId(),
    id: `glass-rule-${nextNumber}`,
    name: `Rule ${nextNumber}`,
    enabled: true,
    logic: "all",
    action: "drop",
    conditions: [newCondition()],
  });
  syncJsonFromBuilder();
}

function removeRule(index: number): void {
  builder.rules.splice(index, 1);
  syncJsonFromBuilder();
}

function addCondition(ruleIndex: number): void {
  builder.rules[ruleIndex]?.conditions.push(newCondition());
  syncJsonFromBuilder();
}

function removeCondition(ruleIndex: number, conditionIndex: number): void {
  builder.rules[ruleIndex]?.conditions.splice(conditionIndex, 1);
  syncJsonFromBuilder();
}

function onConditionValueSourceChange(condition: BuilderCondition): void {
  if (condition.valueSource === "group") {
    condition.groupKind = condition.groupKind || "channel_hash_groups";
    const names = groupNamesForKind(condition.groupKind);
    condition.groupId = condition.groupId || names[0] || "";
  }
  syncJsonFromBuilder();
}

function onConditionGroupKindChange(condition: BuilderCondition): void {
  const names = groupNamesForKind(condition.groupKind);
  condition.groupId = names.includes(condition.groupId || "") ? condition.groupId : names[0] || "";
  syncJsonFromBuilder();
}

function moveCondition(ruleIndex: number, conditionIndex: number, delta: number): void {
  const conditions = builder.rules[ruleIndex]?.conditions;
  if (!conditions) return;
  const nextIndex = conditionIndex + delta;
  if (nextIndex < 0 || nextIndex >= conditions.length) return;
  const [item] = conditions.splice(conditionIndex, 1);
  conditions.splice(nextIndex, 0, item);
  syncJsonFromBuilder();
}

function parseObjectsJson(): Record<string, unknown> {
  try {
    const parsed = JSON.parse(builder.objectsJson || "{}");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function objectGroupsForKind(kind: PolicyObjectGroupKind): Record<string, string[]> {
  const raw = policyObjects.value[kind];
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const output: Record<string, string[]> = {};
  for (const [name, values] of Object.entries(raw as Record<string, unknown>)) {
    if (Array.isArray(values)) {
      output[name] = values.map((value) => String(value));
    }
  }
  return output;
}

function selectedObjectGroupValues(name: string): string[] {
  return objectGroupsForKind(groupForm.kind)[name] || [];
}

function groupNamesForKind(kind?: PolicyObjectGroupKind): string[] {
  if (!kind) return [];
  return Object.keys(objectGroupsForKind(kind)).sort((a, b) => a.localeCompare(b));
}

function addObjectGroup(): void {
  const name = normalizeGroupName(groupForm.name);
  if (!name) {
    showErrorToast("Group name is required.");
    return;
  }
  updateObjectGroups((objects) => {
    const groups = ensureObjectGroupContainer(objects, groupForm.kind);
    groups[name] = Array.isArray(groups[name]) ? groups[name] : [];
  });
  groupForm.name = name;
}

function removeObjectGroup(name: string): void {
  if (!name) return;
  updateObjectGroups((objects) => {
    const groups = ensureObjectGroupContainer(objects, groupForm.kind);
    delete groups[name];
  });
  groupForm.name = "";
}

function addObjectGroupEntry(): void {
  const name = selectedObjectGroupName.value;
  const entry = groupForm.entryValue.trim();
  if (!name || !entry) {
    showErrorToast("Select a group and enter a value.");
    return;
  }
  updateObjectGroups((objects) => {
    const groups = ensureObjectGroupContainer(objects, groupForm.kind);
    const values = Array.isArray(groups[name]) ? groups[name].map((value) => String(value)) : [];
    if (!values.includes(entry)) values.push(entry);
    groups[name] = values;
  });
  groupForm.entryValue = "";
}

function removeObjectGroupEntry(name: string, entry: string): void {
  updateObjectGroups((objects) => {
    const groups = ensureObjectGroupContainer(objects, groupForm.kind);
    groups[name] = (Array.isArray(groups[name]) ? groups[name] : []).filter((value) => String(value) !== entry);
  });
}

function updateObjectGroups(mutator: (objects: Record<string, unknown>) => void): void {
  const objects = JSON.parse(JSON.stringify(policyObjects.value || {})) as Record<string, unknown>;
  mutator(objects);
  builder.objectsJson = JSON.stringify(objects, null, 2);
  syncJsonFromBuilder();
}

function ensureObjectGroupContainer(objects: Record<string, unknown>, kind: PolicyObjectGroupKind): Record<string, unknown[]> {
  if (!objects[kind] || typeof objects[kind] !== "object" || Array.isArray(objects[kind])) {
    objects[kind] = {};
  }
  return objects[kind] as Record<string, unknown[]>;
}

function normalizeGroupName(name: string): string {
  return name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

function groupKindLabel(kind: PolicyObjectGroupKind): string {
  return kind === "channel_hash_groups" ? "channel hash groups" : "pubkey groups";
}

function newCondition(): BuilderCondition {
  return {
    localId: newLocalId(),
    field: "hop_count",
    op: "greater_than",
    value: "2",
    valueType: "number",
    valueSource: "literal",
    groupKind: "channel_hash_groups",
    groupId: "",
  };
}

function syncJsonFromBuilder(): void {
  const policy = policyFromBuilder({ quiet: true });
  if (policy) {
    form.policyJson = JSON.stringify(policy, null, 2);
  }
  validation.value = null;
}

function loadBuilderFromJson(options: { silent?: boolean } = {}): boolean {
  try {
    const parsed = JSON.parse(form.policyJson);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("Policy JSON must be an object.");
    }
    applyPolicyToBuilder(unwrapPolicyEngine(parsed as Record<string, unknown>));
    return true;
  } catch (error) {
    if (!options.silent) {
      showErrorToast(error instanceof Error ? error.message : "Failed to load JSON into visual editor");
    }
    return false;
  }
}

function policyFromBuilder(options: { quiet?: boolean } = {}): Record<string, unknown> | null {
  let objects: Record<string, unknown>;
  try {
    const parsedObjects = JSON.parse(builder.objectsJson || "{}");
    if (!parsedObjects || typeof parsedObjects !== "object" || Array.isArray(parsedObjects)) {
      throw new Error("Objects must be a JSON object.");
    }
    objects = parsedObjects as Record<string, unknown>;
  } catch (error) {
    if (!options.quiet) {
      showErrorToast(error instanceof Error ? error.message : "Objects JSON is invalid.");
    }
    return null;
  }

  return {
    enabled: builder.enabled,
    default_action: builder.defaultAction,
    rules: builder.rules.map((rule, index) => ({
      id: rule.id || `glass-rule-${index + 1}`,
      name: rule.name || `Rule ${index + 1}`,
      enabled: rule.enabled,
      if: {
        [rule.logic]: rule.conditions.map((condition) => ({
          field: condition.field,
          op: condition.op,
          value: conditionValueForPolicy(condition),
        })),
      },
      then: { action: rule.action },
    })),
    objects,
  };
}

function applyPolicyToBuilder(policy: Record<string, unknown>): void {
  builder.enabled = Boolean(policy.enabled ?? true);
  builder.defaultAction = isAction(policy.default_action) ? policy.default_action : "allow";
  const objects = policy.objects && typeof policy.objects === "object" && !Array.isArray(policy.objects) ? policy.objects : {};
  builder.objectsJson = JSON.stringify(objects, null, 2);
  const rules = Array.isArray(policy.rules) ? policy.rules : [];
  builder.rules.splice(0, builder.rules.length, ...rules.map(toBuilderRule));
}

function toBuilderRule(value: unknown, index: number): BuilderRule {
  const rule = value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
  const conditionBlock = rule.if && typeof rule.if === "object" && !Array.isArray(rule.if) ? (rule.if as Record<string, unknown>) : {};
  const logic: Logic = Array.isArray(conditionBlock.any) ? "any" : "all";
  const rawConditions = Array.isArray(conditionBlock[logic]) ? conditionBlock[logic] : [];
  const thenBlock = rule.then && typeof rule.then === "object" && !Array.isArray(rule.then) ? (rule.then as Record<string, unknown>) : {};
  const actionCandidate = thenBlock.action ?? rule.action;
  return {
    localId: newLocalId(),
    id: String(rule.id ?? `glass-rule-${index + 1}`),
    name: String(rule.name ?? `Rule ${index + 1}`),
    enabled: Boolean(rule.enabled ?? true),
    logic,
    action: isAction(actionCandidate) ? actionCandidate : "allow",
    conditions: rawConditions.map(toBuilderCondition),
  };
}

function toBuilderCondition(value: unknown): BuilderCondition {
  const condition = value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
  const rawValue = condition.value;
  const groupRef = typeof rawValue === "string" && rawValue.startsWith("@");
  const groupParts = groupRef ? rawValue.slice(1).split(".", 2) : [];
  const groupKind: PolicyObjectGroupKind = groupParts[0] === "pubkey_groups" ? "pubkey_groups" : "channel_hash_groups";
  const groupId = groupParts[1] || "";
  return {
    localId: newLocalId(),
    field: String(condition.field ?? "hop_count"),
    op: String(condition.op ?? condition.operator ?? "equals"),
    value: stringifyConditionValue(rawValue),
    valueType: inferValueType(rawValue),
    valueSource: groupRef ? "group" : "literal",
    groupKind,
    groupId,
  };
}

function conditionValueForPolicy(condition: BuilderCondition): unknown {
  if (condition.valueSource === "group") {
    const groupKind = condition.groupKind || "channel_hash_groups";
    const fallbackId = condition.value.trim().replace(/^@?[^.]+\./, "");
    const groupId = condition.groupId || fallbackId;
    return groupId ? `@${groupKind}.${groupId}` : `@${groupKind}`;
  }
  return parseConditionValue(condition.value, condition.valueType);
}

function parseConditionValue(value: string, valueType: RuleValueType): unknown {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (valueType === "boolean") return trimmed === "true";
  if (valueType === "number") {
    const parsed = Number(trimmed);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return trimmed;
}

function inferValueType(value: unknown): RuleValueType {
  if (typeof value === "boolean") return "boolean";
  if (typeof value === "number") return "number";
  return "string";
}

function stringifyConditionValue(value: unknown): string {
  if (typeof value === "string") return value;
  if (value === undefined) return "";
  return JSON.stringify(value);
}

function unwrapPolicyEngine(policy: Record<string, unknown>): Record<string, unknown> {
  const nested = policy.policy_engine;
  if (nested && typeof nested === "object" && !Array.isArray(nested)) {
    return nested as Record<string, unknown>;
  }
  return policy;
}

function newLocalId(): string {
  return `local-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function isAction(value: unknown): value is Action {
  return value === "allow" || value === "drop" || value === "log_only";
}

function ruleCount(policy: Record<string, unknown>): number {
  return Array.isArray(policy.rules) ? policy.rules.length : 0;
}

function formatCommandId(commandId: string | null): string {
  if (!commandId) return "—";
  return commandId.length > 14 ? `${commandId.slice(0, 8)}…${commandId.slice(-4)}` : commandId;
}
</script>

<style scoped>
.policy-json {
  min-height: 22rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
}

.objects-json {
  min-height: 12rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
}

.clickable-row {
  cursor: pointer;
}

.clickable-row.selected {
  background: rgba(34, 211, 238, 0.08);
}

.muted-block {
  display: block;
  color: rgb(148 163 184);
  font-size: 0.8rem;
  margin-top: 0.25rem;
}

.checkbox-grid {
  display: grid;
  gap: 0.5rem;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
}

.toggle-row.compact {
  margin: 0;
}

.example-template-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
}

.sync-status-table {
  table-layout: fixed;
}

.sync-status-table th:nth-child(1),
.sync-status-table td:nth-child(1) {
  width: 38%;
}

.sync-status-table th:nth-child(2),
.sync-status-table td:nth-child(2) {
  width: 7.5rem;
}

.sync-status-table th:nth-child(3),
.sync-status-table td:nth-child(3) {
  width: 12rem;
}

.sync-status-table th:nth-child(4),
.sync-status-table td:nth-child(4) {
  width: 13rem;
}

.command-id {
  display: inline-block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  vertical-align: middle;
  white-space: nowrap;
}

.nowrap-cell {
  white-space: nowrap;
}

.editor-mode-row,
.policy-section-header,
.rule-header,
.rule-actions,
.rule-title-wrap {
  align-items: center;
  display: flex;
  gap: 0.75rem;
}

.editor-mode-row,
.policy-section-header,
.rule-header {
  justify-content: space-between;
}

.policy-builder {
  display: grid;
  gap: 1rem;
}

.tab-section {
  background: color-mix(in srgb, var(--color-background-mute) 62%, var(--color-surface) 38%);
}

.builder-tab-row {
  justify-content: flex-start;
}

.policy-builder-section,
.rule-card {
  border: 1px solid var(--color-border-subtle);
  border-radius: 1rem;
  padding: 1rem;
  background: color-mix(in srgb, var(--color-surface) 78%, var(--color-background-mute) 22%);
}

.policy-section-title,
.condition-title {
  color: var(--color-text-primary);
  font-weight: 700;
  margin: 0;
}

.builder-toggle {
  align-self: end;
  min-height: 2.75rem;
}

.rule-title-wrap {
  flex: 1;
}

.rule-number {
  align-items: center;
  background: rgba(34, 211, 238, 0.15);
  border: 1px solid rgba(34, 211, 238, 0.35);
  border-radius: 999px;
  color: rgb(103 232 249);
  display: inline-flex;
  font-weight: 700;
  height: 2rem;
  justify-content: center;
  width: 2rem;
}

.grow {
  flex: 1;
}

.condition-list {
  display: grid;
  gap: 0.75rem;
  margin-top: 1rem;
}

.compact-header {
  margin-bottom: -0.25rem;
}

.condition-row {
  align-items: end;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: minmax(160px, 1fr) minmax(140px, 0.8fr) minmax(180px, 1fr) auto;
}

.condition-remove {
  margin-bottom: 0.1rem;
}

.group-ref-controls {
  display: grid;
  gap: 0.35rem;
  min-width: 13rem;
}

.empty-state.small {
  padding: 0.7rem;
}

.policy-group-list,
.policy-group-entry-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin: 0.75rem 0;
}

.policy-group-chip,
.entry-pill {
  align-items: center;
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-radius: 999px;
  display: inline-flex;
  gap: 0.4rem;
  padding: 0.35rem 0.65rem;
}

.policy-group-chip {
  background: color-mix(in srgb, var(--color-surface) 82%, var(--color-background-mute) 18%);
  color: var(--color-text-primary);
}

.policy-group-chip.selected {
  border-color: rgba(34, 211, 238, 0.7);
  color: rgb(103 232 249);
}

.policy-group-chip span {
  color: rgb(148 163 184);
  font-size: 0.75rem;
}

.entry-pill {
  background: rgba(34, 211, 238, 0.08);
  color: var(--color-text-primary);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
  font-size: 0.8rem;
}

.entry-pill button {
  color: rgb(248 113 113);
}

.group-entry-actions {
  justify-content: end;
}

code {
  color: rgb(103 232 249);
}

@media (max-width: 900px) {
  .rule-header,
  .policy-section-header,
  .rule-actions,
  .rule-title-wrap,
  .editor-mode-row {
    align-items: stretch;
    flex-direction: column;
  }

  .condition-row {
    grid-template-columns: 1fr;
  }
}
</style>
