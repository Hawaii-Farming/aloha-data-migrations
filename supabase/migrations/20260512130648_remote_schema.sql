drop view if exists "public"."edi_qb_expense_summary";

drop view if exists "public"."edi_qb_invoice_summary";

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



