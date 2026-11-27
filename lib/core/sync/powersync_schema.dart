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
// Gene - Nov, 27, 2026: Added Server v11 columns and exported both local-only powerSyncSchema and replicated powerSyncReplicatedSchema via activePowerSyncSchema().
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
  // Server v11 replicated columns beyond the original local schema:
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
