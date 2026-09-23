import 'package:powersync/powersync.dart';

/// PowerSync client schema for Switch Fiber Tech.
///
/// PowerSync's SQLite database is the app's only local store. Every table
/// below is declared `localOnly` for now: the Switch Fiber REST API is still
/// the transport that pulls records down and pushes technician edits back
/// (see the sync workers), and the PowerSync Cloud instance is not yet
/// replicating the backend database. A local-only table records nothing in
/// PowerSync's upload queue, which keeps a REST pull of 900 rows from being
/// queued straight back to the server as 900 uploads.
///
/// Once sync rules exist for a table, change its `Table.localOnly(...)` to
/// `Table(...)`, drop the matching REST pull, and route its edits through
/// [SwitchFiberBackendConnector.uploadData]. Nothing else in the app needs
/// to change: reads already go through `watch` on these views.
///
/// Conventions: PowerSync manages `id` as TEXT, so the API's integer ids are
/// stored as their decimal string. Dates are ISO-8601 text, booleans are
/// 0/1 integers, and `raw_json` keeps the untouched API record so an update
/// can replay every field the app does not model.
const Schema powerSyncSchema = Schema([
  jobOrdersTable,
  serviceOrdersTable,
  lcpNapLocationsTable,
  syncErrorLogsTable,
]);

/// Installations: Scheduled, Rescheduled, Activated, Completed.
const Table jobOrdersTable = Table('job_orders', [
  Column.text('ticket_number'),
  Column.text('customer_name'),
  Column.text('contact_number'),
  Column.text('address'),
  Column.text('barangay'),
  Column.text('city'),
  Column.text('plan_name'),
  Column.integer('plan_id'),
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
  Column.text('modified_date'),
  Column.text('raw_json'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
], indexes: [
  Index('job_status_idx', [IndexedColumn('status')]),
  Index('job_assigned_email_idx', [IndexedColumn('assigned_email')]),
  Index('job_is_synced_idx', [IndexedColumn('is_synced')]),
]);

/// Repairs, relocations, swaps and pullouts.
const Table serviceOrdersTable = Table('service_orders', [
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
  Column.text('visit_remarks'),
  Column.text('assigned_email'),
  Column.text('created_date'),
  Column.text('date_installed'),
  Column.text('new_router_modem_sn'),
  Column.text('new_lcp'),
  Column.text('new_nap'),
  Column.text('new_port'),
  Column.text('new_vlan'),
  Column.text('router_model'),
  Column.text('pullout_router_model'),
  Column.text('pullout_router_model_sn'),
  Column.text('pullout_remarks'),
  Column.text('materials_used_json'),
  Column.text('client_signature'),
  Column.text('image1'),
  Column.text('image2'),
  Column.text('image3'),
  Column.text('house_front_picture'),
  Column.text('address_coordinates'),
  Column.real('service_charge'),
  Column.text('raw_json'),
  Column.integer('is_synced'),
  Column.text('updated_at'),
], indexes: [
  Index('so_support_status_idx', [IndexedColumn('support_status')]),
  Index('so_assigned_email_idx', [IndexedColumn('assigned_email')]),
  Index('so_is_synced_idx', [IndexedColumn('is_synced')]),
]);

/// Plant records: LCP cabinets and NAP distribution boxes. Read-only mirror
/// of the server.
const Table lcpNapLocationsTable = Table.localOnly('lcp_nap_locations', [
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
], indexes: [
  Index('lcp_idx', [IndexedColumn('lcp')]),
  Index('nap_idx', [IndexedColumn('nap')]),
]);

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
