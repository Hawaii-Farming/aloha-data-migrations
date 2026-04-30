# SPS Commerce EDI Integration

This document describes how the Hawaii Farming exchanges EDI documents with retail trading partners (Costco, Safeway, etc.) through SPS Commerce. The flow inbounds buyer Purchase Orders (850), outbounds Advance Ship Notices (856) and Invoices (810), and round-trips Functional Acknowledgements (997).

The schema additions for this integration live at migrations `20260401000112` through `20260401000132`.

---

## 1. Document Lifecycle

End-to-end document exchange between buyer, SPS, and Aloha:

```mermaid
sequenceDiagram
    participant B as Buyer (Costco)
    participant S as SPS Commerce
    participant A as Aloha

    B->>S: Customer PO
    S->>A: 850 Purchase Order
    Note over A: edi_inbound_message (raw payload)
    Note over A: sales_po + sales_po_line<br/>status = Received
    A->>S: 997 Functional Acknowledgement
    A->>S: 855 PO Acknowledgement (if required)
    Note over A: status = Acknowledged

    Note over A: Logistics approves<br/>status = Approved
    Note over A: Packhouse packs<br/>+ palletizes + containerizes
    Note over A: Build sales_shipment<br/>+ container + asn + cartons
    A->>S: 856 Advance Ship Notice
    S->>B: 856 forwarded
    S-->>A: 997 acknowledgement of 856
    Note over A: status = Shipped

    A->>S: 810 Invoice (if required)
    S->>B: 810 forwarded
    Note over A: status = Invoiced
```

### Status state machine (`sales_po.status`)

The same column carries both the manual-entry flow and the EDI flow; manual orders skip Received/Acknowledged and EDI orders skip Fulfilled/Unfulfilled/Past Due.

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Draft: Manual entry
    [*] --> Received: 850 ingested
    Received --> Acknowledged: 997 + 855 sent
    Draft --> Approved: Logistics approves
    Acknowledged --> Approved: Logistics approves
    Approved --> Shipped: 856 sent
    Shipped --> Invoiced: 810 sent
    Approved --> Fulfilled: Manual completion
    Approved --> Unfulfilled: Product unavailable
    Approved --> Past_Due: order_date passed without ship
    Invoiced --> [*]
    Fulfilled --> [*]
    Unfulfilled --> [*]
    Past_Due --> [*]
```

---

## 2. Document Reference

| X12 Set | Direction | Purpose | Stored In |
|---------|-----------|---------|-----------|
| 850 | Inbound | Purchase Order | `edi_inbound_message` (raw) → `sales_po`, `sales_po_line` (parsed) |
| 855 | Outbound | PO Acknowledgement | (transient — sent immediately on parse) |
| 856 | Outbound | Advance Ship Notice | `sales_shipment` + `sales_shipment_container` + `sales_po_asn` + `sales_po_asn_carton` |
| 810 | Outbound | Invoice | (built on demand from `sales_po` + `sales_po_asn`) |
| 860 | Inbound | PO Change | `edi_inbound_message` → updates existing `sales_po` |
| 997 | Both | Functional Acknowledgement | Inbound: `edi_inbound_message.acknowledgement_*` columns. Outbound: sent immediately on parse. |

---

## 3. Trading Partner Setup

Onboarding a new buyer requires three records before the first 850 can be ingested:

1. `sales_customer` — the buyer as a regular customer in our app
2. `sales_trading_partner` — the EDI bridge: `sps_partner_id`, `sps_vendor_number`, plus flags for which document flows are required (`asn_required`, `invoice_required`, `acknowledgement_required`)
3. `sales_product_buyer_part` rows — one per (buyer, our product) pair, mapping the buyer's part number to our `sales_product`. Without this row, inbound 850 line items will not resolve and the parse will fail.

`sales_trading_partner.sps_partner_id` is the routing key. The inbound parser uses it to find the right trading partner row from the buyer code in the 850 envelope.

---

## 4. Inbound 850 Flow

1. SPS delivers the 850 (X12 or SPS XML) via SFTP / API.
2. Worker writes the raw payload to `edi_inbound_message` with `document_type = '850'`, `parsed_at = NULL`.
3. Parser reads each unparsed message:
   - Looks up `sales_trading_partner` by `sps_partner_id` from the envelope.
   - Creates one `sales_po` row with `sales_trading_partner_id` set, `status = 'Received'`, snapshot of all `ship_to_*` / `bill_to_*` / `buyer_*` / `carrier_*` / `requested_*_date` / `payment_terms_net_days` fields from the 850 segments.
   - For each PO line, looks up `sales_product_buyer_part` by `(sales_customer_id, buyer_part_number)` to resolve `sales_product_id`. Creates `sales_po_line` with the snapshot of `buyer_part_number`, `buyer_description`, `buyer_uom`, `buyer_line_sequence`, `gtin_case`.
   - On success, sets `parsed_at = now()` and `sales_po_id = <new PO id>`.
   - On failure, sets `parse_error` and leaves `parsed_at` NULL.
4. Worker sends the 997 Functional Acknowledgement back to SPS within 24h (mandatory). Result is recorded on `edi_inbound_message.acknowledgement_status` / `acknowledgement_sent_at`.
5. If `sales_trading_partner.acknowledgement_required = true`, worker also sends an 855 PO Acknowledgement confirming acceptance/rejection per line.

**Failure modes and recovery:**
- Unknown `sps_partner_id` → parse fails. Add the trading partner row, then replay (set `parsed_at = NULL` and re-process).
- Unknown `buyer_part_number` → parse fails. Add the missing `sales_product_buyer_part` row, then replay.
- Bad XML / X12 → parse fails with descriptive `parse_error`. Often an SPS-side issue; reach out via SPS support and reference `sps_message_id`.

---

## 5. Outbound 856 ASN Flow

The 856 is generated when a PO ships. The hierarchy splits booking, container, and per-document state:

```
sales_shipment                  (booking — carrier, BOL, ship_date)
  └─ sales_shipment_container   (each physical container/trailer — number, seal, type)
      └─ sales_po_asn           (one per PO per container — 856 envelope, sent_at, acknowledgement)
          └─ sales_po_asn_carton (cartons with SSCC labels)
```

Real-world examples this models:
- **Young Brothers ocean booking, two reefers** — one `sales_shipment` row (carrier YOBR, master BOL, booking_number); two `sales_shipment_container` rows (one cucumber reefer, one lettuce reefer, each with its own container_number and seal). POs in the cucumber reefer get ASN rows tied to that container; POs in the lettuce reefer tie to the other.
- **Trucking to Costco DC** — one `sales_shipment` row (carrier SCAC, BOL); one `sales_shipment_container` row (the trailer); multiple `sales_po_asn` rows under that container if several POs ride the truck.
- **PO split across two containers** — two `sales_po_asn` rows for the same PO, one per container.

Workflow:
1. Warehouse marks `sales_po.status = 'Shipped'` (typically when the truck or barge departs).
2. Worker checks `sales_trading_partner.asn_required`. If true:
   - Find or create the `sales_shipment` row for this booking (carrier_scac, BOL, booking_number, ship_date).
   - Find or create the `sales_shipment_container` row for the container the goods are loaded in (container_number, seal_number, sales_container_type_id, optional reefer setpoint).
   - Insert a `sales_po_asn` row referencing the container. The `(sales_shipment_container_id, sales_po_id)` UNIQUE constraint prevents duplicate ASNs for a PO on the same container.
   - Insert one `sales_po_asn_carton` row per physical carton with the GS1 SSCC-18 barcode (the UCC-128 label barcode).
   - For pallet-level grouping (Tare → Pack hierarchy), use `parent_carton_id` on the case rows pointing at a Tare-type pallet row. Flat case-only ASNs leave `parent_carton_id` NULL.
   - Build the 856 X12 / XML (joining shipment + container + asn + cartons), transmit to SPS, set `sent_at` on the ASN and store the verbatim payload in `raw_outbound`.
3. SPS returns a 997 acknowledging receipt. Worker updates `acknowledged_at` and `status = 'Acknowledged'` on the ASN (or `Rejected` on functional failure). Each PO's 856 is acknowledged independently.

**SSCC notes:**
- SSCC-18 is globally unique and must NEVER be reused, even if the shipment is cancelled. The `uq_sales_po_asn_carton_sscc` UNIQUE constraint enforces this at the DB level.
- The SSCC is what the buyer scans on receipt. Mismatch between physical label and 856 SN1/MAN segment means the carton gets refused at the dock.

**Catch-weight cartons:**
- `actual_net_weight` + `weight_uom` are required only when `sales_product.is_catch_weight = true`. Fixed-weight products use the `sales_product` defaults and leave these NULL.

---

## 6. Outbound 810 Invoice Flow

1. Triggered from a finalized `sales_po_asn` (we don't invoice unshipped POs).
2. Worker checks `sales_trading_partner.invoice_required`. Some partners self-invoice from receipt and skip 810 — for those, skip this step.
3. Build the 810 from `sales_po` (header — `po_number`, `payment_terms_net_days`, `bill_to_*`) + `sales_po_line` (lines — `buyer_part_number`, `buyer_line_sequence`, `gtin_case`, `price_per_case`) + `sales_po_asn` → `sales_shipment_container` → `sales_shipment` (container number, BOL reference).
4. Transmit, then set `sales_po.status = 'Invoiced'`.

The 810 is built on demand and not persisted to its own table; the source data is fully captured on `sales_po` + lines + ASN, so re-rendering is deterministic.

---

## 7. Schema Reference

### New tables (slot 145–153)
- `sales_trading_partner` — EDI bridge from `sps_partner_id` to `sales_customer`. Declares which doc flows are required.
- `sales_product_buyer_part` — `(sales_customer_id, buyer_part_number)` → `sales_product_id` lookup. Required for 850 line resolution.
- `edi_inbound_message` — raw archive of every inbound document. Audit trail and replay source.
- `sales_shipment` — booking / voyage record. Carrier, BOL, booking_number, ship_date, ETA. One row per booking.
- `sales_shipment_container` — physical container / trailer in a booking. Container number, seal, container type, reefer setpoint. One row per box; ocean bookings have several, trucking has one.
- `sales_po_asn` — outbound 856 header. One row per PO per container; FKs to `sales_shipment_container`.
- `sales_po_asn_carton` — carton-level detail with SSCC-18 labels. Self-referencing for pallet→case nesting.

### Extended tables
- `sales_po` (slot 114): EDI fields baked in — `sales_trading_partner_id`, `buyer_department`, `buyer_division`, `buyer_contact_*`, `ship_to_*`, `bill_to_*`, `carrier_scac`, `carrier_routing`, `requested_ship_date`, `requested_delivery_date`, `payment_terms_net_days`. The existing `po_number` column carries the buyer's PO number from 850 BEG for EDI orders. Status CHECK includes EDI lifecycle states `Received`, `Acknowledged`, `Shipped`, `Invoiced` alongside the manual-flow states.
- `sales_po_line` (slot 115): buyer_part fields baked in — `buyer_part_number`, `buyer_description`, `buyer_uom`, `buyer_line_sequence`, `gtin_case`. All snapshots at PO receipt — once captured here, edits to `sales_product_buyer_part` won't retroactively rewrite history.

Every SPS-only column on `sales_po` and `sales_po_line` carries an `EDI-only.` prefix in its `COMMENT ON COLUMN` so the EDI provenance is visible from `\d+ sales_po` / `\d+ sales_po_line` in psql.

---

## 8. Security & RLS

All seven new tables follow the standard RLS pattern: `org_id IN (SELECT public.get_user_org_ids())` for SELECT to `authenticated`, no INSERT/UPDATE/DELETE policy (mutations flow through the service-role key in server-side workers). The same convention applies as the rest of the schema — see `supabase/migrations/20260401000200_sys_rls_policies.sql`.

The EDI worker runs server-side with the service-role key; browser clients never write to these tables directly.
