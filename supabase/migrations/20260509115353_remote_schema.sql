alter table "public"."sales_pallet" drop constraint "sales_pallet_sales_sps_shipment_container_id_fkey";

alter table "public"."sales_po" drop constraint "sales_po_sales_sps_trading_partner_id_fkey";

alter table "public"."sales_sps_edi_inbound_message" drop constraint "sales_sps_edi_inbound_message_acknowledgement_status_check";

alter table "public"."sales_sps_edi_inbound_message" drop constraint "sales_sps_edi_inbound_message_org_id_fkey";

alter table "public"."sales_sps_edi_inbound_message" drop constraint "sales_sps_edi_inbound_message_sales_po_id_fkey";

alter table "public"."sales_sps_edi_inbound_message" drop constraint "sales_sps_edi_inbound_message_sales_sps_trading_partner_id_fkey";

alter table "public"."sales_sps_po_asn" drop constraint "sales_sps_po_asn_org_id_fkey";

alter table "public"."sales_sps_po_asn" drop constraint "sales_sps_po_asn_sales_po_id_fkey";

alter table "public"."sales_sps_po_asn" drop constraint "sales_sps_po_asn_sales_sps_shipment_container_id_fkey";

alter table "public"."sales_sps_po_asn" drop constraint "sales_sps_po_asn_status_check";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_carton_type_check";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_org_id_fkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_pack_lot_id_fkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_parent_carton_id_fkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_sales_po_fulfillment_id_fkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_sales_po_line_id_fkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_sales_sps_po_asn_id_fkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_weight_uom_fkey";

alter table "public"."sales_sps_product_buyer_part" drop constraint "sales_sps_product_buyer_part_org_id_fkey";

alter table "public"."sales_sps_product_buyer_part" drop constraint "sales_sps_product_buyer_part_sales_customer_id_fkey";

alter table "public"."sales_sps_product_buyer_part" drop constraint "sales_sps_product_buyer_part_sales_product_id_fkey";

alter table "public"."sales_sps_shipment" drop constraint "sales_sps_shipment_org_id_fkey";

alter table "public"."sales_sps_shipment_container" drop constraint "sales_sps_shipment_container_org_id_fkey";

alter table "public"."sales_sps_shipment_container" drop constraint "sales_sps_shipment_container_sales_container_type_id_fkey";

alter table "public"."sales_sps_shipment_container" drop constraint "sales_sps_shipment_container_sales_sps_shipment_id_fkey";

alter table "public"."sales_sps_shipment_container" drop constraint "sales_sps_shipment_container_temperature_uom_fkey";

alter table "public"."sales_sps_trading_partner" drop constraint "sales_sps_trading_partner_org_id_fkey";

alter table "public"."sales_sps_trading_partner" drop constraint "sales_sps_trading_partner_sales_customer_id_fkey";

drop view if exists "public"."edi_qb_expense_summary";

drop view if exists "public"."edi_qb_invoice_summary";

alter table "public"."sales_sps_edi_inbound_message" drop constraint "sales_sps_edi_inbound_message_pkey";

alter table "public"."sales_sps_po_asn" drop constraint "sales_sps_po_asn_pkey";

alter table "public"."sales_sps_po_asn_carton" drop constraint "sales_sps_po_asn_carton_pkey";

alter table "public"."sales_sps_product_buyer_part" drop constraint "sales_sps_product_buyer_part_pkey";

alter table "public"."sales_sps_shipment" drop constraint "sales_sps_shipment_pkey";

alter table "public"."sales_sps_shipment_container" drop constraint "sales_sps_shipment_container_pkey";

alter table "public"."sales_sps_trading_partner" drop constraint "sales_sps_trading_partner_pkey";

drop index if exists "public"."sales_sps_edi_inbound_message_pkey";

drop index if exists "public"."sales_sps_po_asn_carton_pkey";

drop index if exists "public"."sales_sps_po_asn_pkey";

drop index if exists "public"."sales_sps_product_buyer_part_pkey";

drop index if exists "public"."sales_sps_shipment_container_pkey";

drop index if exists "public"."sales_sps_shipment_pkey";

drop index if exists "public"."sales_sps_trading_partner_pkey";

CREATE UNIQUE INDEX sales_edi_inbound_message_pkey ON public.sales_sps_edi_inbound_message USING btree (id);

CREATE UNIQUE INDEX sales_po_asn_carton_pkey ON public.sales_sps_po_asn_carton USING btree (id);

CREATE UNIQUE INDEX sales_po_asn_pkey ON public.sales_sps_po_asn USING btree (id);

CREATE UNIQUE INDEX sales_product_buyer_part_pkey ON public.sales_sps_product_buyer_part USING btree (id);

CREATE UNIQUE INDEX sales_shipment_container_pkey ON public.sales_sps_shipment_container USING btree (id);

CREATE UNIQUE INDEX sales_shipment_pkey ON public.sales_sps_shipment USING btree (id);

CREATE UNIQUE INDEX sales_trading_partner_pkey ON public.sales_sps_trading_partner USING btree (id);

alter table "public"."sales_sps_edi_inbound_message" add constraint "sales_edi_inbound_message_pkey" PRIMARY KEY using index "sales_edi_inbound_message_pkey";

alter table "public"."sales_sps_po_asn" add constraint "sales_po_asn_pkey" PRIMARY KEY using index "sales_po_asn_pkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_pkey" PRIMARY KEY using index "sales_po_asn_carton_pkey";

alter table "public"."sales_sps_product_buyer_part" add constraint "sales_product_buyer_part_pkey" PRIMARY KEY using index "sales_product_buyer_part_pkey";

alter table "public"."sales_sps_shipment" add constraint "sales_shipment_pkey" PRIMARY KEY using index "sales_shipment_pkey";

alter table "public"."sales_sps_shipment_container" add constraint "sales_shipment_container_pkey" PRIMARY KEY using index "sales_shipment_container_pkey";

alter table "public"."sales_sps_trading_partner" add constraint "sales_trading_partner_pkey" PRIMARY KEY using index "sales_trading_partner_pkey";

alter table "public"."sales_pallet" add constraint "sales_pallet_sales_shipment_container_id_fkey" FOREIGN KEY (sales_sps_shipment_container_id) REFERENCES public.sales_sps_shipment_container(id) not valid;

alter table "public"."sales_pallet" validate constraint "sales_pallet_sales_shipment_container_id_fkey";

alter table "public"."sales_po" add constraint "sales_po_sales_trading_partner_id_fkey" FOREIGN KEY (sales_sps_trading_partner_id) REFERENCES public.sales_sps_trading_partner(id) not valid;

alter table "public"."sales_po" validate constraint "sales_po_sales_trading_partner_id_fkey";

alter table "public"."sales_sps_edi_inbound_message" add constraint "sales_edi_inbound_message_acknowledgement_status_check" CHECK ((acknowledgement_status = ANY (ARRAY['Accepted'::text, 'AcceptedWithErrors'::text, 'Rejected'::text]))) not valid;

alter table "public"."sales_sps_edi_inbound_message" validate constraint "sales_edi_inbound_message_acknowledgement_status_check";

alter table "public"."sales_sps_edi_inbound_message" add constraint "sales_edi_inbound_message_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_edi_inbound_message" validate constraint "sales_edi_inbound_message_org_id_fkey";

alter table "public"."sales_sps_edi_inbound_message" add constraint "sales_edi_inbound_message_sales_po_id_fkey" FOREIGN KEY (sales_po_id) REFERENCES public.sales_po(id) not valid;

alter table "public"."sales_sps_edi_inbound_message" validate constraint "sales_edi_inbound_message_sales_po_id_fkey";

alter table "public"."sales_sps_edi_inbound_message" add constraint "sales_edi_inbound_message_sales_trading_partner_id_fkey" FOREIGN KEY (sales_sps_trading_partner_id) REFERENCES public.sales_sps_trading_partner(id) not valid;

alter table "public"."sales_sps_edi_inbound_message" validate constraint "sales_edi_inbound_message_sales_trading_partner_id_fkey";

alter table "public"."sales_sps_po_asn" add constraint "sales_po_asn_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_po_asn" validate constraint "sales_po_asn_org_id_fkey";

alter table "public"."sales_sps_po_asn" add constraint "sales_po_asn_sales_po_id_fkey" FOREIGN KEY (sales_po_id) REFERENCES public.sales_po(id) not valid;

alter table "public"."sales_sps_po_asn" validate constraint "sales_po_asn_sales_po_id_fkey";

alter table "public"."sales_sps_po_asn" add constraint "sales_po_asn_sales_shipment_container_id_fkey" FOREIGN KEY (sales_sps_shipment_container_id) REFERENCES public.sales_sps_shipment_container(id) not valid;

alter table "public"."sales_sps_po_asn" validate constraint "sales_po_asn_sales_shipment_container_id_fkey";

alter table "public"."sales_sps_po_asn" add constraint "sales_po_asn_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Sent'::text, 'Acknowledged'::text, 'Rejected'::text, 'Cancelled'::text]))) not valid;

alter table "public"."sales_sps_po_asn" validate constraint "sales_po_asn_status_check";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_carton_type_check" CHECK ((carton_type = ANY (ARRAY['Tare'::text, 'Pack'::text, 'Item'::text]))) not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_carton_type_check";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_org_id_fkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_pack_lot_id_fkey" FOREIGN KEY (pack_lot_id) REFERENCES public.pack_lot(id) not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_pack_lot_id_fkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_parent_carton_id_fkey" FOREIGN KEY (parent_carton_id) REFERENCES public.sales_sps_po_asn_carton(id) ON DELETE CASCADE not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_parent_carton_id_fkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_sales_po_asn_id_fkey" FOREIGN KEY (sales_sps_po_asn_id) REFERENCES public.sales_sps_po_asn(id) ON DELETE CASCADE not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_sales_po_asn_id_fkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_sales_po_fulfillment_id_fkey" FOREIGN KEY (sales_po_fulfillment_id) REFERENCES public.sales_po_fulfillment(id) not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_sales_po_fulfillment_id_fkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_sales_po_line_id_fkey" FOREIGN KEY (sales_po_line_id) REFERENCES public.sales_po_line(id) not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_sales_po_line_id_fkey";

alter table "public"."sales_sps_po_asn_carton" add constraint "sales_po_asn_carton_weight_uom_fkey" FOREIGN KEY (weight_uom) REFERENCES public.sys_uom(id) not valid;

alter table "public"."sales_sps_po_asn_carton" validate constraint "sales_po_asn_carton_weight_uom_fkey";

alter table "public"."sales_sps_product_buyer_part" add constraint "sales_product_buyer_part_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_product_buyer_part" validate constraint "sales_product_buyer_part_org_id_fkey";

alter table "public"."sales_sps_product_buyer_part" add constraint "sales_product_buyer_part_sales_customer_id_fkey" FOREIGN KEY (sales_customer_id) REFERENCES public.sales_customer(id) not valid;

alter table "public"."sales_sps_product_buyer_part" validate constraint "sales_product_buyer_part_sales_customer_id_fkey";

alter table "public"."sales_sps_product_buyer_part" add constraint "sales_product_buyer_part_sales_product_id_fkey" FOREIGN KEY (sales_product_id) REFERENCES public.sales_product(id) not valid;

alter table "public"."sales_sps_product_buyer_part" validate constraint "sales_product_buyer_part_sales_product_id_fkey";

alter table "public"."sales_sps_shipment" add constraint "sales_shipment_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_shipment" validate constraint "sales_shipment_org_id_fkey";

alter table "public"."sales_sps_shipment_container" add constraint "sales_shipment_container_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_shipment_container" validate constraint "sales_shipment_container_org_id_fkey";

alter table "public"."sales_sps_shipment_container" add constraint "sales_shipment_container_sales_container_type_id_fkey" FOREIGN KEY (sales_container_type_id) REFERENCES public.sales_container_type(id) not valid;

alter table "public"."sales_sps_shipment_container" validate constraint "sales_shipment_container_sales_container_type_id_fkey";

alter table "public"."sales_sps_shipment_container" add constraint "sales_shipment_container_sales_shipment_id_fkey" FOREIGN KEY (sales_sps_shipment_id) REFERENCES public.sales_sps_shipment(id) ON DELETE CASCADE not valid;

alter table "public"."sales_sps_shipment_container" validate constraint "sales_shipment_container_sales_shipment_id_fkey";

alter table "public"."sales_sps_shipment_container" add constraint "sales_shipment_container_temperature_uom_fkey" FOREIGN KEY (temperature_uom) REFERENCES public.sys_uom(id) not valid;

alter table "public"."sales_sps_shipment_container" validate constraint "sales_shipment_container_temperature_uom_fkey";

alter table "public"."sales_sps_trading_partner" add constraint "sales_trading_partner_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."sales_sps_trading_partner" validate constraint "sales_trading_partner_org_id_fkey";

alter table "public"."sales_sps_trading_partner" add constraint "sales_trading_partner_sales_customer_id_fkey" FOREIGN KEY (sales_customer_id) REFERENCES public.sales_customer(id) not valid;

alter table "public"."sales_sps_trading_partner" validate constraint "sales_trading_partner_sales_customer_id_fkey";

create or replace view "public"."edi_qb_expense_summary" as  SELECT h.org_id,
    h.payee_name,
    h.account_name AS funding_account,
    h.is_credit,
    h.transaction_date,
    l.line_num,
    l.account_name AS expense_account,
    l.class_name,
    l.description,
    l.amount
   FROM (public.edi_qb_expense h
     LEFT JOIN public.edi_qb_expense_line l ON (((l.org_id = h.org_id) AND (l.expense_id = h.id))));


create or replace view "public"."edi_qb_invoice_summary" as  SELECT h.org_id,
    h.customer_name,
    sc.sales_customer_group_id AS customer_group,
    h.invoice_number,
    h.invoice_date,
    l.line_num,
    l.service_date,
    l.item_name,
    sp.farm_id AS farm,
    l.cases,
    l.amount,
    (l.cases * sp.case_net_weight) AS pounds
   FROM (((public.edi_qb_invoice h
     LEFT JOIN public.edi_qb_invoice_line l ON (((l.org_id = h.org_id) AND (l.invoice_id = h.id))))
     LEFT JOIN public.sales_customer sc ON (((sc.org_id = h.org_id) AND (sc.id = h.customer_name))))
     LEFT JOIN public.sales_product sp ON (((sp.org_id = h.org_id) AND (sp.id = l.item_name))));



