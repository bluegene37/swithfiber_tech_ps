import 'package:powersync/powersync.dart';

import '../constants/app_constants.dart';

/// PowerSync client schema for Switch Fiber Tech.
///
/// PowerSync's SQLite database is the app's only local store. When
/// `POWERSYNC_ENDPOINT` is configured, [activePowerSyncSchema] returns
/// [powerSyncReplicatedSchema] where `job_orders`, `service_orders`, and
/// `lcp_nap_locations` sync directly from the self-hosted PowerSync service
/// and enqueue outbound edits in `ps_crud`. When unconfigured, it uses
/// [powerSyncSchema] (`localOnly`) with REST sync workers.
///
/// Conventions: PowerSync manages `id` as TEXT, so the API's integer ids are
/// stored as their decimal string. Dates are ISO-8601 text, booleans are
/// 0/1 integers, and `raw_json` keeps the untouched API record when present.
/*
const Schema powerSyncSchema = Schema([
  jobOrdersTable,
  serviceOrdersTable,
  lcpNapLocationsTable,
  syncErrorLogsTable,
]);
*/
/*
// Gene - Nov, 26, 2026: Added workTimingHistoryTable to store every Start/Finish/Stop session per user ID and date.
const Schema powerSyncSchema = Schema([
  jobOrdersTable,
  serviceOrdersTable,
  lcpNapLocationsTable,
  syncErrorLogsTable,
  workTimingHistoryTable,
]);
*/
// Gene - Nov, 28, 2026: Upgraded PowerSync schema to v12: canonical item_name_1..10/item_quantity_1..10, new local indexes, 11 cached localOnly lookup tables, and localOnly operational tables (pending_attachments, sync_conflicts, local_id_map).
/*
// Gene - Nov, 27, 2026: Added Server v11 columns and exported both local-only powerSyncSchema and replicated powerSyncReplicatedSchema via activePowerSyncSchema().
const List<Column> _jobOrdersColumns = [
...
  Column.text('item_name1'),
  Column.text('item_quantity1'),
  Column.text('item_name2'),
  Column.text('item_quantity2'),
  Column.text('item_name3'),
  Column.text('item_quantity3'),
  Column.text('item_name4'),
  Column.text('item_quantity4'),
  Column.text('item_name5'),
  Column.text('item_quantity5'),
  Column.text('item_name6'),
  Column.text('item_quantity6'),
  Column.text('item_name7'),
  Column.text('item_quantity7'),
  Column.text('item_name8'),
  Column.text('item_quantity8'),
  Column.text('item_name9'),
  Column.text('item_quantity9'),
  Column.text('item_name10'),
  Column.text('item_quantity10'),
  // Client metadata columns (null on server-replicated rows):
  Column.text('raw_json'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
];

const List<Index> _jobOrdersIndexes = [
  Index('job_status_idx', [IndexedColumn('status')]),
  Index('job_assigned_email_idx', [IndexedColumn('assigned_email')]),
  Index('job_is_synced_idx', [IndexedColumn('is_synced')]),
];
*/
const List<Column> _jobOrdersColumns = [
  Column.text('ticket_number'),
  Column.text('customer_name'),
  Column.text('contact_number'),
  Column.text('address'),
  Column.text('barangay'),
  Column.text('city'),
  Column.text('plan_name'),
  Column.integer('plan_id'),
  Column.text('subscriber_email'),
  Column.text('second_contact_number'),
  Column.text('status'),
  Column.text('onsite_status'),
  Column.text('onsite_remarks'),
  Column.text('status_remarks'),
  Column.real('optical_power'),
  Column.text('modem_router_sn'),
  Column.text('router_model'),
  Column.integer('lcp_id'),
  Column.integer('nap_id'),
  Column.text('nap'),
  Column.text('port_id'),
  Column.integer('vlan_id'),
  Column.text('date_installed'),
  Column.text('box_reading_image'),
  Column.text('router_reading_image'),
  Column.text('client_signature'),
  Column.text('setup_image'),
  Column.text('speedtest_image'),
  Column.text('port_label_image'),
  Column.text('signed_contract_image'),
  Column.text('house_front'),
  Column.text('assigned_email'),
  Column.text('start_timestamp'),
  Column.text('end_timestamp'),
  Column.text('modified_date'),
  Column.text('address_coordinates'),
  Column.text('installation_landmark'),
  Column.text('usage_type'),
  Column.text('renter'),
  Column.text('duration'),
  Column.text('applicant_email'),
  Column.text('username'),
  Column.text('connection_type'),
  Column.text('visit_by'),
  Column.text('visit_with'),
  Column.text('visit_with_other'),
  Column.text('remarks'),
  Column.text('jo_remarks'),
  Column.text('application_id'),
  Column.text('lcp'),
  Column.text('port'),
  Column.text('vlan'),
  Column.text('provider'),
  Column.text('region'),
  Column.text('location'),
  Column.text('modified_by'),
  Column.text('item_name_1'),
  Column.text('item_quantity_1'),
  Column.text('item_name_2'),
  Column.text('item_quantity_2'),
  Column.text('item_name_3'),
  Column.text('item_quantity_3'),
  Column.text('item_name_4'),
  Column.text('item_quantity_4'),
  Column.text('item_name_5'),
  Column.text('item_quantity_5'),
  Column.text('item_name_6'),
  Column.text('item_quantity_6'),
  Column.text('item_name_7'),
  Column.text('item_quantity_7'),
  Column.text('item_name_8'),
  Column.text('item_quantity_8'),
  Column.text('item_name_9'),
  Column.text('item_quantity_9'),
  Column.text('item_name_10'),
  Column.text('item_quantity_10'),
  // Client metadata columns (null on server-replicated rows):
  Column.text('raw_json'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
];

const List<Index> _jobOrdersIndexes = [
  Index('job_status_idx', [IndexedColumn('status')]),
  Index('job_onsite_status_idx', [IndexedColumn('onsite_status')]),
  Index('job_modified_date_idx', [IndexedColumn('modified_date')]),
  Index('job_assigned_email_idx', [IndexedColumn('assigned_email')]),
  Index('job_is_synced_idx', [IndexedColumn('is_synced')]),
];

const List<Column> _serviceOrdersColumns = [
  Column.text('account_number'),
  Column.text('full_name'),
  Column.text('contact_number'),
  Column.text('email_address'),
  Column.text('address'),
  Column.text('barangay'),
  Column.text('city'),
  Column.text('provider'),
  Column.text('plan'),
  Column.text('username'),
  Column.text('connection_type'),
  Column.text('router_modem_sn'),
  Column.text('lcp'),
  Column.text('nap'),
  Column.text('port'),
  Column.text('vlan'),
  Column.text('support_status'),
  Column.text('concern'),
  Column.text('priority_level'),
  Column.text('visit_status'),
  Column.text('visit_by'),
  Column.text('visit_with'),
  Column.text('visit_with_others'),
  Column.text('visit_remarks'),
  Column.text('assigned_email'),
  Column.text('created_date'),
  Column.text('date_installed'),
  Column.text('repair_category'),
  Column.text('connection_remarks'),
  Column.text('new_router_modem_sn'),
  Column.text('new_lcp'),
  Column.text('new_nap'),
  Column.text('new_port'),
  Column.text('new_vlan'),
  Column.text('new_plan'),
  Column.text('router_model'),
  Column.text('pullout_router_model'),
  Column.text('pullout_router_model_sn'),
  Column.text('pullout_cpe_sn'),
  Column.text('pullout_remarks'),
  Column.text('start_timestamp'),
  Column.text('stop_timestamp'),
  Column.text('modified_by'),
  Column.text('modified_date'),
  Column.text('tech_modified_date'),
  Column.text('user_email'),
  Column.text('materials_used_json'),
  Column.text('client_signature'),
  Column.text('image1'),
  Column.text('image2'),
  Column.text('image3'),
  Column.text('house_front_picture'),
  Column.text('address_coordinates'),
  Column.real('service_charge'),
/*
  // Server v11 replicated columns beyond the original local schema:
  Column.text('support_remarks'),
  Column.text('assigned_by'),
  Column.text('assigned_date'),
  Column.text('requested_by'),
  Column.text('duration'),
  Column.text('item_name'),
  Column.text('item_quantity'),
  Column.text('item_name1'),
  Column.text('item_quantity1'),
  Column.text('item_name2'),
  Column.text('item_quantity2'),
  Column.text('item_name3'),
  Column.text('item_quantity3'),
  Column.text('item_name4'),
  Column.text('item_quantity4'),
  Column.text('item_name5'),
  Column.text('item_quantity5'),
  Column.text('item_name6'),
  Column.text('item_quantity6'),
  Column.text('item_name7'),
  Column.text('item_quantity7'),
  Column.text('item_name8'),
  Column.text('item_quantity8'),
  Column.text('item_name9'),
  Column.text('item_quantity9'),
  Column.text('item_name10'),
  Column.text('item_quantity10'),
  // Client metadata columns (null on server-replicated rows):
  Column.text('raw_json'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
];

const List<Index> _serviceOrdersIndexes = [
  Index('so_support_status_idx', [IndexedColumn('support_status')]),
  Index('so_assigned_email_idx', [IndexedColumn('assigned_email')]),
  Index('so_is_synced_idx', [IndexedColumn('is_synced')]),
];
*/
  // Gene - Nov, 28, 2026: Canonical v12 service_orders columns (item_name_1..10 / item_quantity_1..10, visit_status index).
  Column.text('support_remarks'),
  Column.text('assigned_by'),
  Column.text('assigned_date'),
  Column.text('requested_by'),
  Column.text('duration'),
  Column.text('item_name_1'),
  Column.text('item_quantity_1'),
  Column.text('item_name_2'),
  Column.text('item_quantity_2'),
  Column.text('item_name_3'),
  Column.text('item_quantity_3'),
  Column.text('item_name_4'),
  Column.text('item_quantity_4'),
  Column.text('item_name_5'),
  Column.text('item_quantity_5'),
  Column.text('item_name_6'),
  Column.text('item_quantity_6'),
  Column.text('item_name_7'),
  Column.text('item_quantity_7'),
  Column.text('item_name_8'),
  Column.text('item_quantity_8'),
  Column.text('item_name_9'),
  Column.text('item_quantity_9'),
  Column.text('item_name_10'),
  Column.text('item_quantity_10'),
  // Client metadata columns (null on server-replicated rows):
  Column.text('raw_json'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
];

const List<Index> _serviceOrdersIndexes = [
  Index('so_visit_status_idx', [IndexedColumn('visit_status')]),
  Index('so_support_status_idx', [IndexedColumn('support_status')]),
  Index('so_assigned_email_idx', [IndexedColumn('assigned_email')]),
  Index('so_is_synced_idx', [IndexedColumn('is_synced')]),
];

const List<Column> _lcpNapColumns = [
  Column.text('lcp'),
  Column.text('nap'),
  Column.text('lcp_nap'),
  Column.integer('port_total'),
  Column.text('coordinates'),
  Column.text('street'),
  Column.text('barangay'),
  Column.text('city'),
  Column.text('region'),
  Column.text('image'),
  Column.text('image2'),
  Column.text('reading_image'),
  Column.text('modified_by'),
  Column.text('user_email'),
  Column.text('modified_date'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
];

const List<Index> _lcpNapIndexes = [
  Index('lcp_idx', [IndexedColumn('lcp')]),
  Index('nap_idx', [IndexedColumn('nap')]),
  Index('lcp_nap_is_synced_idx', [IndexedColumn('is_synced')]),
];

/*
/// Local-only PowerSync schema used when `POWERSYNC_ENDPOINT` is unconfigured.
const Schema powerSyncSchema = Schema([
  jobOrdersTable,
  serviceOrdersTable,
  lcpNapLocationsTable,
  syncErrorLogsTable,
  workTimingHistoryTable,
]);

/// Replicated PowerSync schema used when connected to the self-hosted PowerSync service.
const Schema powerSyncReplicatedSchema = Schema([
  jobOrdersReplicatedTable,
  serviceOrdersReplicatedTable,
  lcpNapLocationsReplicatedTable,
  syncErrorLogsTable,
  workTimingHistoryTable,
]);
*/
// Gene - Nov, 28, 2026: PowerSync v12 schemas include the 11 cached lookup tables and 3 local-only operational tables in both local-only and replicated modes.
const Schema powerSyncSchema = Schema([
  jobOrdersTable,
  serviceOrdersTable,
  lcpNapLocationsTable,
  syncErrorLogsTable,
  workTimingHistoryTable,
  inventoryItemsTable,
  inventoryCategoriesTable,
  inventoryLogsTable,
  plansTable,
  lcpTable,
  napTable,
  vlansTable,
  lcpNapTable,
  portsTable,
  lcpNapPortsTable,
  routersTable,
  pendingAttachmentsTable,
  syncConflictsTable,
  localIdMapTable,
]);

const Schema powerSyncReplicatedSchema = Schema([
  jobOrdersReplicatedTable,
  serviceOrdersReplicatedTable,
  lcpNapLocationsReplicatedTable,
  syncErrorLogsTable,
  workTimingHistoryTable,
  inventoryItemsTable,
  inventoryCategoriesTable,
  inventoryLogsTable,
  plansTable,
  lcpTable,
  napTable,
  vlansTable,
  lcpNapTable,
  portsTable,
  lcpNapPortsTable,
  routersTable,
  pendingAttachmentsTable,
  syncConflictsTable,
  localIdMapTable,
]);

/// Returns [powerSyncReplicatedSchema] when PowerSync cloud sync is active,
/// or [powerSyncSchema] (`localOnly`) otherwise.
Schema activePowerSyncSchema({bool? replicated}) =>
    (replicated ?? AppConstants.isPowerSyncConfigured)
        ? powerSyncReplicatedSchema
        : powerSyncSchema;

/// Installations: Scheduled, Rescheduled, Activated, Completed (local-only table).
const Table jobOrdersTable = Table.localOnly(
  'job_orders',
  _jobOrdersColumns,
  indexes: _jobOrdersIndexes,
);

/// Installations: Scheduled, Rescheduled, Activated, Completed (replicated table).
const Table jobOrdersReplicatedTable = Table(
  'job_orders',
  _jobOrdersColumns,
  indexes: _jobOrdersIndexes,
);

/// Repairs, relocations, swaps and pullouts (local-only table).
const Table serviceOrdersTable = Table.localOnly(
  'service_orders',
  _serviceOrdersColumns,
  indexes: _serviceOrdersIndexes,
);

/// Repairs, relocations, swaps and pullouts (replicated table).
const Table serviceOrdersReplicatedTable = Table(
  'service_orders',
  _serviceOrdersColumns,
  indexes: _serviceOrdersIndexes,
);

/// Plant records: LCP cabinets and NAP distribution boxes (local-only table).
const Table lcpNapLocationsTable = Table.localOnly(
  'lcp_nap_locations',
  _lcpNapColumns,
  indexes: _lcpNapIndexes,
);

/// Plant records: LCP cabinets and NAP distribution boxes (replicated table).
const Table lcpNapLocationsReplicatedTable = Table(
  'lcp_nap_locations',
  _lcpNapColumns,
  indexes: _lcpNapIndexes,
);

/// Every push the server refused, kept on the phone that hit it. Never
/// leaves the device, so it stays local-only whatever the other tables do.
const Table syncErrorLogsTable = Table.localOnly('sync_error_logs', [
  /// Insertion order. Several failures in one sync pass share a timestamp,
  /// so trimming and ordering go by this instead.
  Column.integer('seq'),
  Column.text('entity_type'),
  Column.integer('entity_id'),
  Column.text('reference'),
  Column.text('operation'),
  Column.integer('status_code'),
  Column.text('message'),
  Column.integer('payload_bytes'),
  Column.text('occurred_at'),
  Column.integer('resolved'),
  Column.text('request_method'),
  Column.text('request_url'),
  Column.text('request_body'),
  Column.text('response_body'),
], indexes: [
  Index('sync_error_seq_idx', [IndexedColumn('seq')]),
  Index('sync_error_resolved_idx', [IndexedColumn('resolved')]),
]);

// Gene - Nov, 26, 2026: Local-only table recording every technician Start and Finish/Stop session indexed by user_id and work_date.
const Table workTimingHistoryTable = Table.localOnly('work_timing_history', [
  Column.text('order_type'),
  Column.integer('order_id'),
  Column.text('order_reference'),
  Column.text('customer_name'),
  Column.text('user_id'),
  Column.text('user_name'),
  Column.text('work_date'),
  Column.text('start_time'),
  Column.text('end_time'),
  Column.integer('duration_minutes'),
  Column.integer('is_synced'),
  Column.text('created_at'),
], indexes: [
  Index('wth_user_date_idx',
      [IndexedColumn('user_id'), IndexedColumn('work_date')]),
  Index('wth_order_idx',
      [IndexedColumn('order_type'), IndexedColumn('order_id')]),
]);

// Gene - Nov, 28, 2026: 11 Local-Only Lookup Tables populated via GET /api/sync/lookups.
const Table inventoryItemsTable = Table.localOnly('inventory_items', [
  Column.text('item_id'),
  Column.text('name'),
  Column.text('description'),
  Column.text('category'),
  Column.text('supplier'),
  Column.integer('quantity'),
  Column.text('image'),
  Column.text('user_email'),
  Column.text('modified_by'),
  Column.text('modified_date'),
]);

const Table inventoryCategoriesTable = Table.localOnly('inventory_categories', [
  Column.text('name'),
  Column.text('description'),
  Column.text('modified_by'),
  Column.text('modified_date'),
]);

const Table inventoryLogsTable = Table.localOnly('inventory_logs', [
  Column.text('item_id'),
  Column.integer('quantity'),
  Column.text('requested_by'),
  Column.text('requested_with'),
  Column.text('status'),
  Column.text('remarks'),
  Column.text('created_date'),
]);

const Table plansTable = Table.localOnly('plans', [
  Column.text('name'),
  Column.text('description'),
  Column.real('amount'),
  Column.integer('discount_id'),
  Column.text('created_by'),
  Column.text('created_date'),
  Column.text('modified_by'),
  Column.text('modified_date'),
]);

const List<Column> _namedLookupColumns = [
  Column.text('name'),
  Column.text('description'),
  Column.text('created_by'),
  Column.text('created_date'),
  Column.text('modified_by'),
  Column.text('modified_date'),
];

const Table lcpTable = Table.localOnly('lcp', _namedLookupColumns);
const Table napTable = Table.localOnly('nap', _namedLookupColumns);
const Table vlansTable = Table.localOnly('vlans', _namedLookupColumns);
const Table lcpNapTable = Table.localOnly('lcpnap', _namedLookupColumns);

const List<Column> _portLookupColumns = [
  Column.text('name'),
  Column.text('description'),
  Column.integer('created_by_user_id'),
  Column.text('created_date'),
  Column.integer('modified_by_user_id'),
  Column.text('modified_date'),
];

const Table portsTable = Table.localOnly('ports', _portLookupColumns);
const Table lcpNapPortsTable =
    Table.localOnly('lcpnap_ports', _portLookupColumns);

const Table routersTable = Table.localOnly('routers', [
  Column.text('name'),
  Column.text('description'),
  Column.text('brand'),
  Column.text('model'),
  Column.text('created_by'),
  Column.text('created_date'),
  Column.text('modified_by'),
  Column.text('modified_date'),
]);

// Gene - Nov, 28, 2026: 3 Local-Only Operational Tables for disk-backed multipart photos, non-blocking 409 conflicts, and offline UUID -> server ID mapping.
const Table pendingAttachmentsTable = Table.localOnly(
  'pending_attachments',
  [
    Column.text('entity_type'),
    Column.text('entity_id'),
    Column.text('slot_name'),
    Column.text('file_path'),
    Column.integer('delete_flag'),
    Column.text('status'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ],
  indexes: [
    Index('pending_att_entity_idx', [
      IndexedColumn('entity_type'),
      IndexedColumn('entity_id'),
      IndexedColumn('status'),
    ]),
  ],
);

const Table syncConflictsTable = Table.localOnly(
  'sync_conflicts',
  [
    Column.text('entity_type'),
    Column.text('entity_id'),
    Column.text('reason'),
    Column.integer('status_code'),
    Column.text('message'),
    Column.text('server_snapshot'),
    Column.text('local_payload'),
    Column.integer('resolved'),
    Column.text('created_at'),
  ],
  indexes: [
    Index('sync_conflicts_resolved_idx', [
      IndexedColumn('resolved'),
      IndexedColumn('created_at'),
    ]),
  ],
);

const Table localIdMapTable = Table.localOnly(
  'local_id_map',
  [
    Column.text('entity_type'),
    Column.text('local_id'),
    Column.text('server_id'),
    Column.text('created_at'),
  ],
  indexes: [
    Index('local_id_map_lookup_idx', [
      IndexedColumn('entity_type'),
      IndexedColumn('local_id'),
    ]),
  ],
);
