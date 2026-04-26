export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.4"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      auth_link_log: {
        Row: {
          auth_user_id: string
          employee_id: string
          id: string
          linked_at: string
        }
        Insert: {
          auth_user_id: string
          employee_id: string
          id?: string
          linked_at?: string
        }
        Update: {
          auth_user_id?: string
          employee_id?: string
          id?: string
          linked_at?: string
        }
        Relationships: []
      }
      fin_expense: {
        Row: {
          account_name: string | null
          account_ref: string | null
          amount: number | null
          class_name: string | null
          created_at: string
          created_by: string | null
          description: string | null
          effective_amount: number | null
          farm_name: string | null
          id: string
          is_credit: boolean
          is_deleted: boolean
          macro_category: string | null
          notes: string | null
          org_id: string
          payee_name: string | null
          txn_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          account_name?: string | null
          account_ref?: string | null
          amount?: number | null
          class_name?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          effective_amount?: number | null
          farm_name?: string | null
          id?: string
          is_credit?: boolean
          is_deleted?: boolean
          macro_category?: string | null
          notes?: string | null
          org_id: string
          payee_name?: string | null
          txn_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          account_name?: string | null
          account_ref?: string | null
          amount?: number | null
          class_name?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          effective_amount?: number | null
          farm_name?: string | null
          id?: string
          is_credit?: boolean
          is_deleted?: boolean
          macro_category?: string | null
          notes?: string | null
          org_id?: string
          payee_name?: string | null
          txn_date?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fin_expense_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fin_expense_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      fsafe_lab: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fsafe_lab_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      fsafe_lab_test: {
        Row: {
          atp_site_count: number | null
          created_at: string
          created_by: string | null
          enum_options: Json | null
          enum_pass_options: Json | null
          farm_name: string | null
          is_deleted: boolean
          maximum_value: number | null
          minimum_value: number | null
          org_id: string
          required_retests: number
          required_vector_tests: number
          result_type: string
          test_description: string | null
          test_methods: Json
          test_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          atp_site_count?: number | null
          created_at?: string
          created_by?: string | null
          enum_options?: Json | null
          enum_pass_options?: Json | null
          farm_name?: string | null
          is_deleted?: boolean
          maximum_value?: number | null
          minimum_value?: number | null
          org_id: string
          required_retests?: number
          required_vector_tests?: number
          result_type: string
          test_description?: string | null
          test_methods?: Json
          test_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          atp_site_count?: number | null
          created_at?: string
          created_by?: string | null
          enum_options?: Json | null
          enum_pass_options?: Json | null
          farm_name?: string | null
          is_deleted?: boolean
          maximum_value?: number | null
          minimum_value?: number | null
          org_id?: string
          required_retests?: number
          required_vector_tests?: number
          result_type?: string
          test_description?: string | null
          test_methods?: Json
          test_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fsafe_lab_test_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_lab_test_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      fsafe_pest_result: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          is_deleted: boolean
          notes: string | null
          ops_task_tracker_id: string
          org_id: string
          pest_type: string | null
          photo_url: string | null
          site_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          ops_task_tracker_id: string
          org_id: string
          pest_type?: string | null
          photo_url?: string | null
          site_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          ops_task_tracker_id?: string
          org_id?: string
          pest_type?: string | null
          photo_url?: string | null
          site_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fsafe_pest_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_pest_result_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_pest_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_pest_result_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      fsafe_result: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string | null
          fail_code: string | null
          farm_name: string
          fsafe_lab_name: string | null
          fsafe_lab_test_name: string
          fsafe_result_id_original: string | null
          fsafe_test_hold_id: string | null
          id: string
          initial_retest_vector: string | null
          is_deleted: boolean
          notes: string | null
          org_id: string
          result_enum: string | null
          result_numeric: number | null
          result_pass: boolean | null
          sampled_at: string | null
          sampled_by: string | null
          site_id: string | null
          started_at: string | null
          status: string
          test_method: string | null
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          fail_code?: string | null
          farm_name: string
          fsafe_lab_name?: string | null
          fsafe_lab_test_name: string
          fsafe_result_id_original?: string | null
          fsafe_test_hold_id?: string | null
          id?: string
          initial_retest_vector?: string | null
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          result_enum?: string | null
          result_numeric?: number | null
          result_pass?: boolean | null
          sampled_at?: string | null
          sampled_by?: string | null
          site_id?: string | null
          started_at?: string | null
          status?: string
          test_method?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          fail_code?: string | null
          farm_name?: string
          fsafe_lab_name?: string | null
          fsafe_lab_test_name?: string
          fsafe_result_id_original?: string | null
          fsafe_test_hold_id?: string | null
          id?: string
          initial_retest_vector?: string | null
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          result_enum?: string | null
          result_numeric?: number | null
          result_pass?: boolean | null
          sampled_at?: string | null
          sampled_by?: string | null
          site_id?: string | null
          started_at?: string | null
          status?: string
          test_method?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_fsafe_result_sampled_by"
            columns: ["sampled_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_fsafe_result_sampled_by"
            columns: ["sampled_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_fsafe_result_verified_by"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_fsafe_result_verified_by"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fsafe_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_result_fsafe_lab_name_fkey"
            columns: ["fsafe_lab_name"]
            isOneToOne: false
            referencedRelation: "fsafe_lab"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_result_fsafe_lab_test_name_fkey"
            columns: ["fsafe_lab_test_name"]
            isOneToOne: false
            referencedRelation: "fsafe_lab_test"
            referencedColumns: ["test_name"]
          },
          {
            foreignKeyName: "fsafe_result_fsafe_result_id_original_fkey"
            columns: ["fsafe_result_id_original"]
            isOneToOne: false
            referencedRelation: "fsafe_result"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_result_fsafe_test_hold_id_fkey"
            columns: ["fsafe_test_hold_id"]
            isOneToOne: false
            referencedRelation: "fsafe_test_hold"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_result_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      fsafe_test_hold: {
        Row: {
          created_at: string
          created_by: string | null
          delivered_to_lab_on: string | null
          farm_name: string
          fsafe_lab_name: string | null
          id: string
          is_deleted: boolean
          lab_test_id: string | null
          notes: string | null
          org_id: string
          pack_lot_id: string
          sales_customer_group_name: string | null
          sales_customer_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          delivered_to_lab_on?: string | null
          farm_name: string
          fsafe_lab_name?: string | null
          id?: string
          is_deleted?: boolean
          lab_test_id?: string | null
          notes?: string | null
          org_id: string
          pack_lot_id: string
          sales_customer_group_name?: string | null
          sales_customer_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          delivered_to_lab_on?: string | null
          farm_name?: string
          fsafe_lab_name?: string | null
          id?: string
          is_deleted?: boolean
          lab_test_id?: string | null
          notes?: string | null
          org_id?: string
          pack_lot_id?: string
          sales_customer_group_name?: string | null
          sales_customer_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fsafe_test_hold_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_test_hold_fsafe_lab_name_fkey"
            columns: ["fsafe_lab_name"]
            isOneToOne: false
            referencedRelation: "fsafe_lab"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_test_hold_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_test_hold_pack_lot_id_fkey"
            columns: ["pack_lot_id"]
            isOneToOne: false
            referencedRelation: "pack_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_test_hold_sales_customer_group_name_fkey"
            columns: ["sales_customer_group_name"]
            isOneToOne: false
            referencedRelation: "sales_customer_group"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_test_hold_sales_customer_name_fkey"
            columns: ["sales_customer_name"]
            isOneToOne: false
            referencedRelation: "sales_customer"
            referencedColumns: ["name"]
          },
        ]
      }
      fsafe_test_hold_po: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          fsafe_test_hold_id: string
          id: string
          is_deleted: boolean
          org_id: string
          sales_po_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          fsafe_test_hold_id: string
          id?: string
          is_deleted?: boolean
          org_id: string
          sales_po_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          fsafe_test_hold_id?: string
          id?: string
          is_deleted?: boolean
          org_id?: string
          sales_po_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fsafe_test_hold_po_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fsafe_test_hold_po_fsafe_test_hold_id_fkey"
            columns: ["fsafe_test_hold_id"]
            isOneToOne: false
            referencedRelation: "fsafe_test_hold"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_test_hold_po_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fsafe_test_hold_po_sales_po_id_fkey"
            columns: ["sales_po_id"]
            isOneToOne: false
            referencedRelation: "sales_po"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_cuke_gh_row_planting: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          grow_variety_id: string
          grow_variety_id_2: string | null
          id: string
          is_deleted: boolean
          notes: string | null
          num_bags: number | null
          org_id: string
          org_site_cuke_gh_row_id: string
          plants_per_bag: number
          scenario: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_variety_id: string
          grow_variety_id_2?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          num_bags?: number | null
          org_id: string
          org_site_cuke_gh_row_id: string
          plants_per_bag: number
          scenario: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_variety_id?: string
          grow_variety_id_2?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          num_bags?: number | null
          org_id?: string
          org_site_cuke_gh_row_id?: string
          plants_per_bag?: number
          scenario?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_grow_cuke_gh_row_planting_row"
            columns: ["org_site_cuke_gh_row_id"]
            isOneToOne: false
            referencedRelation: "org_site_cuke_gh_row"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_grow_cuke_gh_row_planting_variety_primary"
            columns: ["grow_variety_id"]
            isOneToOne: false
            referencedRelation: "grow_variety"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_grow_cuke_gh_row_planting_variety_secondary"
            columns: ["grow_variety_id_2"]
            isOneToOne: false
            referencedRelation: "grow_variety"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_cuke_gh_row_planting_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_cuke_gh_row_planting_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_cuke_rotation: {
        Row: {
          anchor_week_start: string | null
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          is_anchor: boolean
          is_deleted: boolean
          notes: string | null
          org_id: string
          site_id: string
          slot_num: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          anchor_week_start?: string | null
          created_at?: string
          created_by?: string | null
          farm_name: string
          id?: string
          is_anchor?: boolean
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          site_id: string
          slot_num: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          anchor_week_start?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          is_anchor?: boolean
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          site_id?: string
          slot_num?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_cuke_rotation_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site_cuke_gh"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_cuke_seed_batch: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          grow_trial_type_name: string | null
          id: string
          invnt_item_name: string | null
          invnt_lot_id: string | null
          is_deleted: boolean
          next_bag_change_date: string | null
          notes: string | null
          ops_task_tracker_id: string | null
          org_id: string
          rows_4_per_bag: number
          rows_5_per_bag: number
          seeding_date: string
          seeds: number
          site_id: string | null
          status: string
          transplant_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_trial_type_name?: string | null
          id?: string
          invnt_item_name?: string | null
          invnt_lot_id?: string | null
          is_deleted?: boolean
          next_bag_change_date?: string | null
          notes?: string | null
          ops_task_tracker_id?: string | null
          org_id: string
          rows_4_per_bag?: number
          rows_5_per_bag?: number
          seeding_date: string
          seeds: number
          site_id?: string | null
          status?: string
          transplant_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_trial_type_name?: string | null
          id?: string
          invnt_item_name?: string | null
          invnt_lot_id?: string | null
          is_deleted?: boolean
          next_bag_change_date?: string | null
          notes?: string | null
          ops_task_tracker_id?: string | null
          org_id?: string
          rows_4_per_bag?: number
          rows_5_per_bag?: number
          seeding_date?: string
          seeds?: number
          site_id?: string | null
          status?: string
          transplant_date?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_cuke_seed_batch_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_cuke_seed_batch_grow_trial_type_name_fkey"
            columns: ["grow_trial_type_name"]
            isOneToOne: false
            referencedRelation: "grow_trial_type"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_cuke_seed_batch_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_cuke_seed_batch_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "grow_cuke_seed_batch_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_cuke_seed_batch_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site_cuke_gh"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_cycle_pattern: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_cycle_pattern_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_cycle_pattern_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_disease: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      grow_fertigation: {
        Row: {
          created_at: string
          created_by: string | null
          equipment_name: string
          farm_name: string
          grow_fertigation_recipe_name: string
          id: string
          is_deleted: boolean
          ops_task_tracker_id: string
          org_id: string
          updated_at: string
          updated_by: string | null
          volume_applied: number
          volume_uom: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          equipment_name: string
          farm_name: string
          grow_fertigation_recipe_name: string
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
          volume_applied: number
          volume_uom: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          equipment_name?: string
          farm_name?: string
          grow_fertigation_recipe_name?: string
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
          volume_applied?: number
          volume_uom?: string
        }
        Relationships: [
          {
            foreignKeyName: "grow_fertigation_equipment_name_fkey"
            columns: ["equipment_name"]
            isOneToOne: false
            referencedRelation: "org_equipment"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_grow_fertigation_recipe_name_fkey"
            columns: ["grow_fertigation_recipe_name"]
            isOneToOne: false
            referencedRelation: "grow_fertigation_recipe"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_fertigation_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_fertigation_volume_uom_fkey"
            columns: ["volume_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      grow_fertigation_recipe: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_fertigation_recipe_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_fertigation_recipe_item: {
        Row: {
          application_per_burn: number | null
          application_quantity: number
          application_uom: string
          burn_uom: string | null
          created_at: string
          created_by: string | null
          equipment_name: string | null
          farm_name: string
          grow_fertigation_recipe_name: string
          id: string
          invnt_item_name: string | null
          is_deleted: boolean
          item_name: string
          notes: string | null
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          application_per_burn?: number | null
          application_quantity: number
          application_uom: string
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          equipment_name?: string | null
          farm_name: string
          grow_fertigation_recipe_name: string
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          item_name: string
          notes?: string | null
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          application_per_burn?: number | null
          application_quantity?: number
          application_uom?: string
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          equipment_name?: string | null
          farm_name?: string
          grow_fertigation_recipe_name?: string
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          item_name?: string
          notes?: string | null
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_fertigation_recipe_item_application_uom_fkey"
            columns: ["application_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_burn_uom_fkey"
            columns: ["burn_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_equipment_name_fkey"
            columns: ["equipment_name"]
            isOneToOne: false
            referencedRelation: "org_equipment"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_grow_fertigation_recipe_name_fkey"
            columns: ["grow_fertigation_recipe_name"]
            isOneToOne: false
            referencedRelation: "grow_fertigation_recipe"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_item_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_fertigation_recipe_site: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          grow_fertigation_recipe_name: string
          id: string
          is_deleted: boolean
          org_id: string
          site_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_fertigation_recipe_name: string
          id?: string
          is_deleted?: boolean
          org_id: string
          site_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_fertigation_recipe_name?: string
          id?: string
          is_deleted?: boolean
          org_id?: string
          site_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_fertigation_recipe_site_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_site_grow_fertigation_recipe_name_fkey"
            columns: ["grow_fertigation_recipe_name"]
            isOneToOne: false
            referencedRelation: "grow_fertigation_recipe"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_site_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_fertigation_recipe_site_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_grade: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          farm_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          farm_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          farm_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_grade_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_grade_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_harvest_container: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          grow_grade_id: string | null
          grow_variety_id: string | null
          is_deleted: boolean
          is_tare_calculated: boolean
          name: string
          org_id: string
          tare_formula: string | null
          tare_formula_inputs: Json | null
          tare_weight: number | null
          updated_at: string
          updated_by: string | null
          weight_uom: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_grade_id?: string | null
          grow_variety_id?: string | null
          is_deleted?: boolean
          is_tare_calculated?: boolean
          name: string
          org_id: string
          tare_formula?: string | null
          tare_formula_inputs?: Json | null
          tare_weight?: number | null
          updated_at?: string
          updated_by?: string | null
          weight_uom: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_grade_id?: string | null
          grow_variety_id?: string | null
          is_deleted?: boolean
          is_tare_calculated?: boolean
          name?: string
          org_id?: string
          tare_formula?: string | null
          tare_formula_inputs?: Json | null
          tare_weight?: number | null
          updated_at?: string
          updated_by?: string | null
          weight_uom?: string
        }
        Relationships: [
          {
            foreignKeyName: "grow_harvest_container_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_harvest_container_grow_grade_id_fkey"
            columns: ["grow_grade_id"]
            isOneToOne: false
            referencedRelation: "grow_grade"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_harvest_container_grow_variety_id_fkey"
            columns: ["grow_variety_id"]
            isOneToOne: false
            referencedRelation: "grow_variety"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_harvest_container_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_container_weight_uom_fkey"
            columns: ["weight_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      grow_harvest_weight: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          gross_weight: number
          grow_cuke_seed_batch_id: string | null
          grow_grade_id: string | null
          grow_harvest_container_name: string
          grow_lettuce_seed_batch_id: string | null
          harvest_date: string
          id: string
          is_deleted: boolean
          net_weight: number
          number_of_containers: number
          ops_task_tracker_id: string | null
          org_id: string
          site_id: string | null
          updated_at: string
          updated_by: string | null
          weight_uom: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          gross_weight: number
          grow_cuke_seed_batch_id?: string | null
          grow_grade_id?: string | null
          grow_harvest_container_name: string
          grow_lettuce_seed_batch_id?: string | null
          harvest_date: string
          id?: string
          is_deleted?: boolean
          net_weight: number
          number_of_containers: number
          ops_task_tracker_id?: string | null
          org_id: string
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
          weight_uom: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          gross_weight?: number
          grow_cuke_seed_batch_id?: string | null
          grow_grade_id?: string | null
          grow_harvest_container_name?: string
          grow_lettuce_seed_batch_id?: string | null
          harvest_date?: string
          id?: string
          is_deleted?: boolean
          net_weight?: number
          number_of_containers?: number
          ops_task_tracker_id?: string | null
          org_id?: string
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
          weight_uom?: string
        }
        Relationships: [
          {
            foreignKeyName: "grow_harvest_weight_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_cuke_seed_batch_id_fkey"
            columns: ["grow_cuke_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_cuke_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_grade_id_fkey"
            columns: ["grow_grade_id"]
            isOneToOne: false
            referencedRelation: "grow_grade"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_harvest_container_name_fkey"
            columns: ["grow_harvest_container_name"]
            isOneToOne: false
            referencedRelation: "grow_harvest_container"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_lettuce_seed_batch_id_fkey"
            columns: ["grow_lettuce_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_lettuce_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_weight_uom_fkey"
            columns: ["weight_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      grow_lettuce_seed_batch: {
        Row: {
          batch_code: string
          created_at: string
          created_by: string | null
          estimated_harvest_date: string
          farm_name: string
          grow_cycle_pattern_name: string | null
          grow_lettuce_seed_mix_name: string | null
          grow_trial_type_name: string | null
          id: string
          invnt_item_name: string | null
          invnt_lot_id: string | null
          is_deleted: boolean
          notes: string | null
          number_of_rows: number
          number_of_units: number
          ops_task_tracker_id: string | null
          org_id: string
          seeding_date: string
          seeding_uom: string
          seeds_per_unit: number
          site_id: string | null
          status: string
          transplant_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          batch_code: string
          created_at?: string
          created_by?: string | null
          estimated_harvest_date: string
          farm_name: string
          grow_cycle_pattern_name?: string | null
          grow_lettuce_seed_mix_name?: string | null
          grow_trial_type_name?: string | null
          id?: string
          invnt_item_name?: string | null
          invnt_lot_id?: string | null
          is_deleted?: boolean
          notes?: string | null
          number_of_rows: number
          number_of_units: number
          ops_task_tracker_id?: string | null
          org_id: string
          seeding_date: string
          seeding_uom: string
          seeds_per_unit: number
          site_id?: string | null
          status?: string
          transplant_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          batch_code?: string
          created_at?: string
          created_by?: string | null
          estimated_harvest_date?: string
          farm_name?: string
          grow_cycle_pattern_name?: string | null
          grow_lettuce_seed_mix_name?: string | null
          grow_trial_type_name?: string | null
          id?: string
          invnt_item_name?: string | null
          invnt_lot_id?: string | null
          is_deleted?: boolean
          notes?: string | null
          number_of_rows?: number
          number_of_units?: number
          ops_task_tracker_id?: string | null
          org_id?: string
          seeding_date?: string
          seeding_uom?: string
          seeds_per_unit?: number
          site_id?: string | null
          status?: string
          transplant_date?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_lettuce_seed_batch_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_grow_cycle_pattern_name_fkey"
            columns: ["grow_cycle_pattern_name"]
            isOneToOne: false
            referencedRelation: "grow_cycle_pattern"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_grow_lettuce_seed_mix_name_fkey"
            columns: ["grow_lettuce_seed_mix_name"]
            isOneToOne: false
            referencedRelation: "grow_lettuce_seed_mix"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_grow_trial_type_name_fkey"
            columns: ["grow_trial_type_name"]
            isOneToOne: false
            referencedRelation: "grow_trial_type"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_invnt_lot_id_fkey"
            columns: ["invnt_lot_id"]
            isOneToOne: false
            referencedRelation: "invnt_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_seeding_uom_fkey"
            columns: ["seeding_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_batch_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_lettuce_seed_mix: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_lettuce_seed_mix_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_mix_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_lettuce_seed_mix_item: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          grow_lettuce_seed_mix_name: string
          id: string
          invnt_item_name: string
          invnt_lot_id: string | null
          is_deleted: boolean
          org_id: string
          percentage: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_lettuce_seed_mix_name: string
          id?: string
          invnt_item_name: string
          invnt_lot_id?: string | null
          is_deleted?: boolean
          org_id: string
          percentage: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_lettuce_seed_mix_name?: string
          id?: string
          invnt_item_name?: string
          invnt_lot_id?: string | null
          is_deleted?: boolean
          org_id?: string
          percentage?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_lettuce_seed_mix_item_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_mix_item_grow_lettuce_seed_mix_name_fkey"
            columns: ["grow_lettuce_seed_mix_name"]
            isOneToOne: false
            referencedRelation: "grow_lettuce_seed_mix"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_mix_item_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_mix_item_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_mix_item_invnt_lot_id_fkey"
            columns: ["invnt_lot_id"]
            isOneToOne: false
            referencedRelation: "invnt_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_lettuce_seed_mix_item_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_monitoring_metric: {
        Row: {
          corrective_actions: Json
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          enum_options: Json | null
          enum_pass_options: Json | null
          farm_name: string
          formula: string | null
          id: string
          input_point_ids: Json | null
          is_calculated: boolean
          is_deleted: boolean
          is_required: boolean
          maximum_value: number | null
          minimum_value: number | null
          name: string
          org_id: string
          reading_uom: string | null
          response_type: string
          site_category: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          corrective_actions?: Json
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          enum_options?: Json | null
          enum_pass_options?: Json | null
          farm_name: string
          formula?: string | null
          id: string
          input_point_ids?: Json | null
          is_calculated?: boolean
          is_deleted?: boolean
          is_required?: boolean
          maximum_value?: number | null
          minimum_value?: number | null
          name: string
          org_id: string
          reading_uom?: string | null
          response_type?: string
          site_category: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          corrective_actions?: Json
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          enum_options?: Json | null
          enum_pass_options?: Json | null
          farm_name?: string
          formula?: string | null
          id?: string
          input_point_ids?: Json | null
          is_calculated?: boolean
          is_deleted?: boolean
          is_required?: boolean
          maximum_value?: number | null
          minimum_value?: number | null
          name?: string
          org_id?: string
          reading_uom?: string | null
          response_type?: string
          site_category?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_monitoring_metric_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_monitoring_metric_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_monitoring_metric_reading_uom_fkey"
            columns: ["reading_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      grow_monitoring_result: {
        Row: {
          corrective_action: string | null
          created_at: string
          created_by: string | null
          farm_name: string
          grow_monitoring_metric_id: string
          id: string
          is_deleted: boolean
          is_out_of_range: boolean
          monitoring_station: string | null
          notes: string | null
          ops_task_tracker_id: string
          org_id: string
          reading: number | null
          reading_boolean: boolean | null
          reading_enum: string | null
          site_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          corrective_action?: string | null
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_monitoring_metric_id: string
          id?: string
          is_deleted?: boolean
          is_out_of_range?: boolean
          monitoring_station?: string | null
          notes?: string | null
          ops_task_tracker_id: string
          org_id: string
          reading?: number | null
          reading_boolean?: boolean | null
          reading_enum?: string | null
          site_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          corrective_action?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_monitoring_metric_id?: string
          id?: string
          is_deleted?: boolean
          is_out_of_range?: boolean
          monitoring_station?: string | null
          notes?: string | null
          ops_task_tracker_id?: string
          org_id?: string
          reading?: number | null
          reading_boolean?: boolean | null
          reading_enum?: string | null
          site_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_monitoring_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_monitoring_result_grow_monitoring_metric_id_fkey"
            columns: ["grow_monitoring_metric_id"]
            isOneToOne: false
            referencedRelation: "grow_monitoring_metric"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_monitoring_result_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_monitoring_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_monitoring_result_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_pest: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      grow_scout_result: {
        Row: {
          created_at: string
          created_by: string | null
          disease_infection_stage: string | null
          farm_name: string
          grow_disease_name: string | null
          grow_pest_name: string | null
          id: string
          is_deleted: boolean
          notes: string | null
          observation_type: string
          ops_task_tracker_id: string
          org_id: string
          severity_level: string
          site_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          disease_infection_stage?: string | null
          farm_name: string
          grow_disease_name?: string | null
          grow_pest_name?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          observation_type: string
          ops_task_tracker_id: string
          org_id: string
          severity_level: string
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          disease_infection_stage?: string | null
          farm_name?: string
          grow_disease_name?: string | null
          grow_pest_name?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          observation_type?: string
          ops_task_tracker_id?: string
          org_id?: string
          severity_level?: string
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_scout_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_scout_result_grow_disease_name_fkey"
            columns: ["grow_disease_name"]
            isOneToOne: false
            referencedRelation: "grow_disease"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_scout_result_grow_pest_name_fkey"
            columns: ["grow_pest_name"]
            isOneToOne: false
            referencedRelation: "grow_pest"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_scout_result_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_scout_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_scout_result_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_spray_compliance: {
        Row: {
          application_method: Json
          application_per_burn: number
          application_uom: string | null
          burn_uom: string | null
          created_at: string
          created_by: string | null
          effective_date: string | null
          epa_registration: string | null
          expiration_date: string | null
          external_label_url: string
          farm_name: string | null
          id: string
          invnt_item_name: string | null
          is_deleted: boolean
          label_date: string | null
          maximum_quantity_per_acre: number | null
          org_id: string
          phi_days: number
          rei_hours: number
          target_pest_disease: Json
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          application_method?: Json
          application_per_burn?: number
          application_uom?: string | null
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          effective_date?: string | null
          epa_registration?: string | null
          expiration_date?: string | null
          external_label_url: string
          farm_name?: string | null
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          label_date?: string | null
          maximum_quantity_per_acre?: number | null
          org_id: string
          phi_days?: number
          rei_hours?: number
          target_pest_disease?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          application_method?: Json
          application_per_burn?: number
          application_uom?: string | null
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          effective_date?: string | null
          epa_registration?: string | null
          expiration_date?: string | null
          external_label_url?: string
          farm_name?: string | null
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          label_date?: string | null
          maximum_quantity_per_acre?: number | null
          org_id?: string
          phi_days?: number
          rei_hours?: number
          target_pest_disease?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_spray_compliance_application_uom_fkey"
            columns: ["application_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_spray_compliance_burn_uom_fkey"
            columns: ["burn_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_spray_compliance_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_spray_compliance_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_spray_compliance_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "grow_spray_compliance_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_spray_equipment: {
        Row: {
          created_at: string
          created_by: string | null
          equipment_name: string
          farm_name: string
          id: string
          is_deleted: boolean
          ops_task_tracker_id: string
          org_id: string
          updated_at: string
          updated_by: string | null
          water_quantity: number
          water_uom: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          equipment_name: string
          farm_name: string
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
          water_quantity: number
          water_uom: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          equipment_name?: string
          farm_name?: string
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
          water_quantity?: number
          water_uom?: string
        }
        Relationships: [
          {
            foreignKeyName: "grow_spray_equipment_equipment_name_fkey"
            columns: ["equipment_name"]
            isOneToOne: false
            referencedRelation: "org_equipment"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_spray_equipment_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_spray_equipment_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_spray_equipment_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_spray_equipment_water_uom_fkey"
            columns: ["water_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      grow_spray_input: {
        Row: {
          application_quantity: number
          application_uom: string
          created_at: string
          created_by: string | null
          farm_name: string
          grow_spray_compliance_id: string
          id: string
          invnt_item_name: string
          invnt_lot_id: string | null
          is_deleted: boolean
          ops_task_tracker_id: string
          org_id: string
          target_pest_disease: Json
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          application_quantity: number
          application_uom: string
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_spray_compliance_id: string
          id?: string
          invnt_item_name: string
          invnt_lot_id?: string | null
          is_deleted?: boolean
          ops_task_tracker_id: string
          org_id: string
          target_pest_disease?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          application_quantity?: number
          application_uom?: string
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_spray_compliance_id?: string
          id?: string
          invnt_item_name?: string
          invnt_lot_id?: string | null
          is_deleted?: boolean
          ops_task_tracker_id?: string
          org_id?: string
          target_pest_disease?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_spray_input_application_uom_fkey"
            columns: ["application_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_spray_input_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_spray_input_grow_spray_compliance_id_fkey"
            columns: ["grow_spray_compliance_id"]
            isOneToOne: false
            referencedRelation: "grow_spray_compliance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_spray_input_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_spray_input_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "grow_spray_input_invnt_lot_id_fkey"
            columns: ["invnt_lot_id"]
            isOneToOne: false
            referencedRelation: "invnt_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_spray_input_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_spray_input_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_task_photo: {
        Row: {
          caption: string | null
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          is_deleted: boolean
          ops_task_tracker_id: string
          org_id: string
          photo_url: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name: string
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id: string
          org_id: string
          photo_url: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id?: string
          org_id?: string
          photo_url?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_task_photo_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_task_photo_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_task_photo_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_task_seed_batch: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          grow_cuke_seed_batch_id: string | null
          grow_lettuce_seed_batch_id: string | null
          id: string
          is_deleted: boolean
          ops_task_tracker_id: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          grow_cuke_seed_batch_id?: string | null
          grow_lettuce_seed_batch_id?: string | null
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          grow_cuke_seed_batch_id?: string | null
          grow_lettuce_seed_batch_id?: string | null
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_task_seed_batch_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_task_seed_batch_grow_cuke_seed_batch_id_fkey"
            columns: ["grow_cuke_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_cuke_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_task_seed_batch_grow_lettuce_seed_batch_id_fkey"
            columns: ["grow_lettuce_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_lettuce_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_task_seed_batch_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_task_seed_batch_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_trial_type: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_trial_type_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_trial_type_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_variety: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_variety_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_variety_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_department: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_department_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_disciplinary_warning: {
        Row: {
          acknowledged_at: string | null
          created_at: string
          created_by: string | null
          employee_signature_url: string | null
          further_infraction_consequences: string | null
          hr_employee_name: string
          id: string
          is_acknowledged: boolean
          is_deleted: boolean
          notes: string | null
          offense_description: string | null
          offense_type: string | null
          org_id: string
          plan_for_improvement: string | null
          reported_at: string
          reported_by: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
          updated_by: string | null
          warning_date: string | null
          warning_type: string | null
        }
        Insert: {
          acknowledged_at?: string | null
          created_at?: string
          created_by?: string | null
          employee_signature_url?: string | null
          further_infraction_consequences?: string | null
          hr_employee_name: string
          id?: string
          is_acknowledged?: boolean
          is_deleted?: boolean
          notes?: string | null
          offense_description?: string | null
          offense_type?: string | null
          org_id: string
          plan_for_improvement?: string | null
          reported_at?: string
          reported_by?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warning_date?: string | null
          warning_type?: string | null
        }
        Update: {
          acknowledged_at?: string | null
          created_at?: string
          created_by?: string | null
          employee_signature_url?: string | null
          further_infraction_consequences?: string | null
          hr_employee_name?: string
          id?: string
          is_acknowledged?: boolean
          is_deleted?: boolean
          notes?: string | null
          offense_description?: string | null
          offense_type?: string | null
          org_id?: string
          plan_for_improvement?: string | null
          reported_at?: string
          reported_by?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warning_date?: string | null
          warning_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hr_disciplinary_warning_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_disciplinary_warning_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_disciplinary_warning_reported_by"
            columns: ["reported_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_disciplinary_warning_reported_by"
            columns: ["reported_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_disciplinary_warning_reviewed_by"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_disciplinary_warning_reviewed_by"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_disciplinary_warning_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_employee: {
        Row: {
          company_email: string | null
          compensation_manager_name: string | null
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          email: string | null
          end_date: string | null
          ethnicity: string | null
          first_name: string
          gender: string | null
          housing_name: string | null
          hr_department_name: string | null
          hr_work_authorization_name: string | null
          is_deleted: boolean
          is_manager: boolean
          is_primary_org: boolean
          last_name: string
          name: string
          org_id: string
          overtime_threshold: number | null
          pay_delivery_method: string | null
          pay_structure: string | null
          payroll_id: string | null
          payroll_processor: string | null
          phone: string | null
          preferred_name: string | null
          profile_photo_url: string | null
          start_date: string | null
          sys_access_level_name: string
          team_lead_name: string | null
          updated_at: string
          updated_by: string | null
          user_id: string | null
          wc: string | null
        }
        Insert: {
          company_email?: string | null
          compensation_manager_name?: string | null
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          email?: string | null
          end_date?: string | null
          ethnicity?: string | null
          first_name: string
          gender?: string | null
          housing_name?: string | null
          hr_department_name?: string | null
          hr_work_authorization_name?: string | null
          is_deleted?: boolean
          is_manager?: boolean
          is_primary_org?: boolean
          last_name: string
          name: string
          org_id: string
          overtime_threshold?: number | null
          pay_delivery_method?: string | null
          pay_structure?: string | null
          payroll_id?: string | null
          payroll_processor?: string | null
          phone?: string | null
          preferred_name?: string | null
          profile_photo_url?: string | null
          start_date?: string | null
          sys_access_level_name: string
          team_lead_name?: string | null
          updated_at?: string
          updated_by?: string | null
          user_id?: string | null
          wc?: string | null
        }
        Update: {
          company_email?: string | null
          compensation_manager_name?: string | null
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          email?: string | null
          end_date?: string | null
          ethnicity?: string | null
          first_name?: string
          gender?: string | null
          housing_name?: string | null
          hr_department_name?: string | null
          hr_work_authorization_name?: string | null
          is_deleted?: boolean
          is_manager?: boolean
          is_primary_org?: boolean
          last_name?: string
          name?: string
          org_id?: string
          overtime_threshold?: number | null
          pay_delivery_method?: string | null
          pay_structure?: string | null
          payroll_id?: string | null
          payroll_processor?: string | null
          phone?: string | null
          preferred_name?: string | null
          profile_photo_url?: string | null
          start_date?: string | null
          sys_access_level_name?: string
          team_lead_name?: string | null
          updated_at?: string
          updated_by?: string | null
          user_id?: string | null
          wc?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hr_employee_compensation_manager"
            columns: ["compensation_manager_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_employee_compensation_manager"
            columns: ["compensation_manager_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_employee_team_lead"
            columns: ["team_lead_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_employee_team_lead"
            columns: ["team_lead_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_employee_housing_name_fkey"
            columns: ["housing_name"]
            isOneToOne: false
            referencedRelation: "org_site_housing"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_employee_hr_department_name_fkey"
            columns: ["hr_department_name"]
            isOneToOne: false
            referencedRelation: "hr_department"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_employee_hr_work_authorization_name_fkey"
            columns: ["hr_work_authorization_name"]
            isOneToOne: false
            referencedRelation: "hr_work_authorization"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_employee_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_employee_sys_access_level_name_fkey"
            columns: ["sys_access_level_name"]
            isOneToOne: false
            referencedRelation: "sys_access_level"
            referencedColumns: ["name"]
          },
        ]
      }
      hr_employee_review: {
        Row: {
          attendance: number
          average: number | null
          created_at: string
          created_by: string | null
          engagement: number
          hr_employee_name: string
          id: string
          is_deleted: boolean
          is_locked: boolean
          lead_name: string | null
          notes: string | null
          org_id: string
          productivity: number
          quality: number
          review_quarter: number
          review_year: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          attendance: number
          average?: number | null
          created_at?: string
          created_by?: string | null
          engagement: number
          hr_employee_name: string
          id?: string
          is_deleted?: boolean
          is_locked?: boolean
          lead_name?: string | null
          notes?: string | null
          org_id: string
          productivity: number
          quality: number
          review_quarter: number
          review_year: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          attendance?: number
          average?: number | null
          created_at?: string
          created_by?: string | null
          engagement?: number
          hr_employee_name?: string
          id?: string
          is_deleted?: boolean
          is_locked?: boolean
          lead_name?: string | null
          notes?: string | null
          org_id?: string
          productivity?: number
          quality?: number
          review_quarter?: number
          review_year?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hr_employee_review_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_employee_review_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_employee_review_lead"
            columns: ["lead_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_employee_review_lead"
            columns: ["lead_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_employee_review_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_employee_review_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_employee_review_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_employee_review_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_employee_review_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
        ]
      }
      hr_module_access: {
        Row: {
          can_delete: boolean
          can_edit: boolean
          can_verify: boolean
          created_at: string
          created_by: string | null
          hr_employee_name: string
          id: string
          is_deleted: boolean
          is_enabled: boolean
          org_id: string
          org_module_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          can_delete?: boolean
          can_edit?: boolean
          can_verify?: boolean
          created_at?: string
          created_by?: string | null
          hr_employee_name: string
          id?: string
          is_deleted?: boolean
          is_enabled?: boolean
          org_id: string
          org_module_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          can_delete?: boolean
          can_edit?: boolean
          can_verify?: boolean
          created_at?: string
          created_by?: string | null
          hr_employee_name?: string
          id?: string
          is_deleted?: boolean
          is_enabled?: boolean
          org_id?: string
          org_module_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_module_access_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_module_access_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_module_access_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_module_access_org_module_name_fkey"
            columns: ["org_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_display_name"]
          },
          {
            foreignKeyName: "hr_module_access_org_module_name_fkey"
            columns: ["org_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_id"]
          },
          {
            foreignKeyName: "hr_module_access_org_module_name_fkey"
            columns: ["org_module_name"]
            isOneToOne: false
            referencedRelation: "org_module"
            referencedColumns: ["name"]
          },
        ]
      }
      hr_payroll: {
        Row: {
          admin_fees: number
          auto_allowance: number
          auto_deduction: number
          bonus_pay: number
          check_date: string
          child_support: number
          comp_plus: number
          created_at: string
          created_by: string | null
          discretionary_overtime_hours: number
          discretionary_overtime_pay: number
          employee_name: string
          fit: number
          funeral_hours: number
          funeral_pay: number
          gross_wage: number
          hawaii_get: number
          hds_dental: number
          health_benefits: number
          holiday_hours: number
          holiday_pay: number
          hourly_rate: number | null
          hr_department_name: string | null
          hr_employee_name: string
          hr_work_authorization_name: string | null
          id: string
          invoice_number: string | null
          is_deleted: boolean
          is_standard: boolean
          labor_tax: number
          medicare: number
          net_pay: number
          org_id: string
          other_charges: number
          other_health_charges: number
          other_pay: number
          other_tax: number
          overtime_hours: number
          overtime_pay: number
          overtime_threshold: number | null
          pay_period_end: string
          pay_period_start: string
          pay_structure: string | null
          payroll_id: string
          payroll_processor: string
          per_diem: number
          pre_tax_401k: number
          program_fees: number
          pto_hours: number
          pto_hours_accrued: number
          pto_pay: number
          regular_hours: number
          regular_pay: number
          salary: number
          sick_hours: number
          sick_pay: number
          sit: number
          social_security: number
          tdi: number
          total_cost: number
          total_hours: number
          updated_at: string
          updated_by: string | null
          wc: string | null
          workers_compensation: number
        }
        Insert: {
          admin_fees?: number
          auto_allowance?: number
          auto_deduction?: number
          bonus_pay?: number
          check_date: string
          child_support?: number
          comp_plus?: number
          created_at?: string
          created_by?: string | null
          discretionary_overtime_hours?: number
          discretionary_overtime_pay?: number
          employee_name: string
          fit?: number
          funeral_hours?: number
          funeral_pay?: number
          gross_wage?: number
          hawaii_get?: number
          hds_dental?: number
          health_benefits?: number
          holiday_hours?: number
          holiday_pay?: number
          hourly_rate?: number | null
          hr_department_name?: string | null
          hr_employee_name: string
          hr_work_authorization_name?: string | null
          id?: string
          invoice_number?: string | null
          is_deleted?: boolean
          is_standard?: boolean
          labor_tax?: number
          medicare?: number
          net_pay?: number
          org_id: string
          other_charges?: number
          other_health_charges?: number
          other_pay?: number
          other_tax?: number
          overtime_hours?: number
          overtime_pay?: number
          overtime_threshold?: number | null
          pay_period_end: string
          pay_period_start: string
          pay_structure?: string | null
          payroll_id: string
          payroll_processor: string
          per_diem?: number
          pre_tax_401k?: number
          program_fees?: number
          pto_hours?: number
          pto_hours_accrued?: number
          pto_pay?: number
          regular_hours?: number
          regular_pay?: number
          salary?: number
          sick_hours?: number
          sick_pay?: number
          sit?: number
          social_security?: number
          tdi?: number
          total_cost?: number
          total_hours?: number
          updated_at?: string
          updated_by?: string | null
          wc?: string | null
          workers_compensation?: number
        }
        Update: {
          admin_fees?: number
          auto_allowance?: number
          auto_deduction?: number
          bonus_pay?: number
          check_date?: string
          child_support?: number
          comp_plus?: number
          created_at?: string
          created_by?: string | null
          discretionary_overtime_hours?: number
          discretionary_overtime_pay?: number
          employee_name?: string
          fit?: number
          funeral_hours?: number
          funeral_pay?: number
          gross_wage?: number
          hawaii_get?: number
          hds_dental?: number
          health_benefits?: number
          holiday_hours?: number
          holiday_pay?: number
          hourly_rate?: number | null
          hr_department_name?: string | null
          hr_employee_name?: string
          hr_work_authorization_name?: string | null
          id?: string
          invoice_number?: string | null
          is_deleted?: boolean
          is_standard?: boolean
          labor_tax?: number
          medicare?: number
          net_pay?: number
          org_id?: string
          other_charges?: number
          other_health_charges?: number
          other_pay?: number
          other_tax?: number
          overtime_hours?: number
          overtime_pay?: number
          overtime_threshold?: number | null
          pay_period_end?: string
          pay_period_start?: string
          pay_structure?: string | null
          payroll_id?: string
          payroll_processor?: string
          per_diem?: number
          pre_tax_401k?: number
          program_fees?: number
          pto_hours?: number
          pto_hours_accrued?: number
          pto_pay?: number
          regular_hours?: number
          regular_pay?: number
          salary?: number
          sick_hours?: number
          sick_pay?: number
          sit?: number
          social_security?: number
          tdi?: number
          total_cost?: number
          total_hours?: number
          updated_at?: string
          updated_by?: string | null
          wc?: string | null
          workers_compensation?: number
        }
        Relationships: [
          {
            foreignKeyName: "hr_payroll_hr_department_name_fkey"
            columns: ["hr_department_name"]
            isOneToOne: false
            referencedRelation: "hr_department"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_payroll_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_payroll_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_payroll_hr_work_authorization_name_fkey"
            columns: ["hr_work_authorization_name"]
            isOneToOne: false
            referencedRelation: "hr_work_authorization"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_payroll_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_time_off_request: {
        Row: {
          created_at: string
          created_by: string | null
          denial_reason: string | null
          hr_employee_name: string
          id: string
          is_deleted: boolean
          non_pto_days: number | null
          notes: string | null
          org_id: string
          pto_days: number | null
          request_reason: string | null
          requested_at: string
          requested_by: string
          return_date: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          sick_leave_days: number | null
          start_date: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          denial_reason?: string | null
          hr_employee_name: string
          id?: string
          is_deleted?: boolean
          non_pto_days?: number | null
          notes?: string | null
          org_id: string
          pto_days?: number | null
          request_reason?: string | null
          requested_at?: string
          requested_by: string
          return_date?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          sick_leave_days?: number | null
          start_date: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          denial_reason?: string | null
          hr_employee_name?: string
          id?: string
          is_deleted?: boolean
          non_pto_days?: number | null
          notes?: string | null
          org_id?: string
          pto_days?: number | null
          request_reason?: string | null
          requested_at?: string
          requested_by?: string
          return_date?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          sick_leave_days?: number | null
          start_date?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hr_time_off_request_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_time_off_request_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_time_off_request_requested_by"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_time_off_request_requested_by"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_time_off_request_reviewed_by"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_time_off_request_reviewed_by"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_time_off_request_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_travel_request: {
        Row: {
          created_at: string
          created_by: string | null
          denial_reason: string | null
          hr_employee_name: string
          id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          request_type: string | null
          requested_at: string
          requested_by: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          travel_from: string | null
          travel_purpose: string | null
          travel_return_date: string | null
          travel_start_date: string | null
          travel_to: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          denial_reason?: string | null
          hr_employee_name: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          request_type?: string | null
          requested_at?: string
          requested_by: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          travel_from?: string | null
          travel_purpose?: string | null
          travel_return_date?: string | null
          travel_start_date?: string | null
          travel_to?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          denial_reason?: string | null
          hr_employee_name?: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          request_type?: string | null
          requested_at?: string
          requested_by?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          travel_from?: string | null
          travel_purpose?: string | null
          travel_return_date?: string | null
          travel_start_date?: string | null
          travel_to?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hr_travel_request_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_travel_request_employee"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_travel_request_requested_by"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_travel_request_requested_by"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_hr_travel_request_reviewed_by"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_travel_request_reviewed_by"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "hr_travel_request_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_work_authorization: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_work_authorization_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      invnt_category: {
        Row: {
          category_name: string
          created_at: string
          created_by: string | null
          id: string
          is_deleted: boolean
          org_id: string
          sub_category_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          category_name: string
          created_at?: string
          created_by?: string | null
          id: string
          is_deleted?: boolean
          org_id: string
          sub_category_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          category_name?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          org_id?: string
          sub_category_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_category_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      invnt_item: {
        Row: {
          burn_per_onhand: number
          burn_per_order: number
          burn_per_week: number
          burn_uom: string | null
          created_at: string
          created_by: string | null
          cushion_weeks: number
          description: string | null
          equipment_name: string | null
          farm_name: string | null
          grow_variety_id: string | null
          invnt_category_id: string | null
          invnt_subcategory_id: string | null
          invnt_vendor_name: string | null
          is_active: boolean
          is_auto_reorder: boolean
          is_deleted: boolean
          is_frequently_used: boolean
          is_palletized: boolean
          maint_part_number: string | null
          maint_part_type: string | null
          manufacturer: string | null
          name: string
          onhand_uom: string | null
          order_per_pallet: number
          order_uom: string | null
          org_id: string
          pallet_per_truckload: number
          photos: Json
          qb_account: string | null
          reorder_point_in_burn: number
          reorder_quantity_in_burn: number
          requires_expiry_date: boolean
          requires_lot_tracking: boolean
          seed_is_pelleted: boolean | null
          site_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          burn_per_onhand?: number
          burn_per_order?: number
          burn_per_week?: number
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          cushion_weeks?: number
          description?: string | null
          equipment_name?: string | null
          farm_name?: string | null
          grow_variety_id?: string | null
          invnt_category_id?: string | null
          invnt_subcategory_id?: string | null
          invnt_vendor_name?: string | null
          is_active?: boolean
          is_auto_reorder?: boolean
          is_deleted?: boolean
          is_frequently_used?: boolean
          is_palletized?: boolean
          maint_part_number?: string | null
          maint_part_type?: string | null
          manufacturer?: string | null
          name: string
          onhand_uom?: string | null
          order_per_pallet?: number
          order_uom?: string | null
          org_id: string
          pallet_per_truckload?: number
          photos?: Json
          qb_account?: string | null
          reorder_point_in_burn?: number
          reorder_quantity_in_burn?: number
          requires_expiry_date?: boolean
          requires_lot_tracking?: boolean
          seed_is_pelleted?: boolean | null
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          burn_per_onhand?: number
          burn_per_order?: number
          burn_per_week?: number
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          cushion_weeks?: number
          description?: string | null
          equipment_name?: string | null
          farm_name?: string | null
          grow_variety_id?: string | null
          invnt_category_id?: string | null
          invnt_subcategory_id?: string | null
          invnt_vendor_name?: string | null
          is_active?: boolean
          is_auto_reorder?: boolean
          is_deleted?: boolean
          is_frequently_used?: boolean
          is_palletized?: boolean
          maint_part_number?: string | null
          maint_part_type?: string | null
          manufacturer?: string | null
          name?: string
          onhand_uom?: string | null
          order_per_pallet?: number
          order_uom?: string | null
          org_id?: string
          pallet_per_truckload?: number
          photos?: Json
          qb_account?: string | null
          reorder_point_in_burn?: number
          reorder_quantity_in_burn?: number
          requires_expiry_date?: boolean
          requires_lot_tracking?: boolean
          seed_is_pelleted?: boolean | null
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_item_burn_uom_fkey"
            columns: ["burn_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_equipment_name_fkey"
            columns: ["equipment_name"]
            isOneToOne: false
            referencedRelation: "org_equipment"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_item_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_item_grow_variety_id_fkey"
            columns: ["grow_variety_id"]
            isOneToOne: false
            referencedRelation: "grow_variety"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_invnt_category_id_fkey"
            columns: ["invnt_category_id"]
            isOneToOne: false
            referencedRelation: "invnt_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_item_invnt_subcategory_id_fkey"
            columns: ["invnt_subcategory_id"]
            isOneToOne: false
            referencedRelation: "invnt_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_item_invnt_vendor_name_fkey"
            columns: ["invnt_vendor_name"]
            isOneToOne: false
            referencedRelation: "invnt_vendor"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_item_onhand_uom_fkey"
            columns: ["onhand_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_order_uom_fkey"
            columns: ["order_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_item_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      invnt_lot: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          invnt_item_name: string
          is_active: boolean
          is_deleted: boolean
          lot_expiry_date: string | null
          lot_number: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          id: string
          invnt_item_name: string
          is_active?: boolean
          is_deleted?: boolean
          lot_expiry_date?: string | null
          lot_number: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          invnt_item_name?: string
          is_active?: boolean
          is_deleted?: boolean
          lot_expiry_date?: string | null
          lot_number?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_lot_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_lot_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_lot_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "invnt_lot_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      invnt_onhand: {
        Row: {
          burn_per_onhand: number
          burn_uom: string | null
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          invnt_item_name: string
          invnt_lot_id: string | null
          is_deleted: boolean
          notes: string | null
          onhand_date: string
          onhand_quantity: number
          onhand_uom: string | null
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          burn_per_onhand?: number
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          invnt_item_name: string
          invnt_lot_id?: string | null
          is_deleted?: boolean
          notes?: string | null
          onhand_date: string
          onhand_quantity: number
          onhand_uom?: string | null
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          burn_per_onhand?: number
          burn_uom?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          invnt_item_name?: string
          invnt_lot_id?: string | null
          is_deleted?: boolean
          notes?: string | null
          onhand_date?: string
          onhand_quantity?: number
          onhand_uom?: string | null
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_onhand_burn_uom_fkey"
            columns: ["burn_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_onhand_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_onhand_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_onhand_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "invnt_onhand_invnt_lot_id_fkey"
            columns: ["invnt_lot_id"]
            isOneToOne: false
            referencedRelation: "invnt_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_onhand_onhand_uom_fkey"
            columns: ["onhand_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_onhand_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      invnt_po: {
        Row: {
          burn_per_order: number
          burn_uom: string
          created_at: string
          created_by: string | null
          expected_delivery_date: string | null
          farm_name: string | null
          id: string
          invnt_category_id: string
          invnt_item_name: string | null
          invnt_vendor_name: string | null
          is_deleted: boolean
          is_freight_included: boolean | null
          item_name: string
          notes: string | null
          order_quantity: number
          order_uom: string
          ordered_at: string | null
          ordered_by: string | null
          org_id: string
          rejected_reason: string | null
          request_photos: Json
          request_type: string
          requested_at: string
          requested_by: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          total_cost: number | null
          tracking_number: string | null
          updated_at: string
          updated_by: string | null
          urgency_level: string | null
          vendor_po_number: string | null
        }
        Insert: {
          burn_per_order?: number
          burn_uom: string
          created_at?: string
          created_by?: string | null
          expected_delivery_date?: string | null
          farm_name?: string | null
          id?: string
          invnt_category_id: string
          invnt_item_name?: string | null
          invnt_vendor_name?: string | null
          is_deleted?: boolean
          is_freight_included?: boolean | null
          item_name: string
          notes?: string | null
          order_quantity: number
          order_uom: string
          ordered_at?: string | null
          ordered_by?: string | null
          org_id: string
          rejected_reason?: string | null
          request_photos?: Json
          request_type?: string
          requested_at?: string
          requested_by: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          total_cost?: number | null
          tracking_number?: string | null
          updated_at?: string
          updated_by?: string | null
          urgency_level?: string | null
          vendor_po_number?: string | null
        }
        Update: {
          burn_per_order?: number
          burn_uom?: string
          created_at?: string
          created_by?: string | null
          expected_delivery_date?: string | null
          farm_name?: string | null
          id?: string
          invnt_category_id?: string
          invnt_item_name?: string | null
          invnt_vendor_name?: string | null
          is_deleted?: boolean
          is_freight_included?: boolean | null
          item_name?: string
          notes?: string | null
          order_quantity?: number
          order_uom?: string
          ordered_at?: string | null
          ordered_by?: string | null
          org_id?: string
          rejected_reason?: string | null
          request_photos?: Json
          request_type?: string
          requested_at?: string
          requested_by?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          total_cost?: number | null
          tracking_number?: string | null
          updated_at?: string
          updated_by?: string | null
          urgency_level?: string | null
          vendor_po_number?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_po_burn_uom_fkey"
            columns: ["burn_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_po_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_invnt_category_id_fkey"
            columns: ["invnt_category_id"]
            isOneToOne: false
            referencedRelation: "invnt_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_po_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "invnt_po_invnt_vendor_name_fkey"
            columns: ["invnt_vendor_name"]
            isOneToOne: false
            referencedRelation: "invnt_vendor"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_order_uom_fkey"
            columns: ["order_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_po_ordered_by_fkey"
            columns: ["ordered_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_ordered_by_fkey"
            columns: ["ordered_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "invnt_po_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_po_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "invnt_po_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
        ]
      }
      invnt_po_received: {
        Row: {
          burn_per_received: number
          created_at: string
          created_by: string | null
          farm_name: string | null
          fsafe_delivery_acceptable: boolean | null
          fsafe_delivery_truck_clean: boolean | null
          id: string
          invnt_lot_id: string | null
          invnt_po_id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          received_at: string
          received_by: string | null
          received_date: string
          received_photos: Json
          received_quantity: number
          received_uom: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          burn_per_received?: number
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          fsafe_delivery_acceptable?: boolean | null
          fsafe_delivery_truck_clean?: boolean | null
          id?: string
          invnt_lot_id?: string | null
          invnt_po_id: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          received_at?: string
          received_by?: string | null
          received_date: string
          received_photos?: Json
          received_quantity: number
          received_uom: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          burn_per_received?: number
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          fsafe_delivery_acceptable?: boolean | null
          fsafe_delivery_truck_clean?: boolean | null
          id?: string
          invnt_lot_id?: string | null
          invnt_po_id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          received_at?: string
          received_by?: string | null
          received_date?: string
          received_photos?: Json
          received_quantity?: number
          received_uom?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_po_received_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_po_received_invnt_lot_id_fkey"
            columns: ["invnt_lot_id"]
            isOneToOne: false
            referencedRelation: "invnt_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_po_received_invnt_po_id_fkey"
            columns: ["invnt_po_id"]
            isOneToOne: false
            referencedRelation: "invnt_po"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_po_received_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_po_received_received_uom_fkey"
            columns: ["received_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      invnt_vendor: {
        Row: {
          address: string | null
          contact_person: string | null
          created_at: string
          created_by: string | null
          email: string | null
          is_deleted: boolean
          name: string
          org_id: string
          payment_terms: string | null
          phone: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          address?: string | null
          contact_person?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          payment_terms?: string | null
          phone?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          address?: string | null
          contact_person?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          payment_terms?: string | null
          phone?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_vendor_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      maint_request: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string | null
          due_date: string | null
          equipment_name: string | null
          farm_name: string | null
          fixer_description: string | null
          fixer_name: string | null
          id: string
          is_deleted: boolean
          org_id: string
          recurring_frequency: string | null
          request_description: string | null
          requested_at: string
          requested_by: string
          site_id: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          equipment_name?: string | null
          farm_name?: string | null
          fixer_description?: string | null
          fixer_name?: string | null
          id?: string
          is_deleted?: boolean
          org_id: string
          recurring_frequency?: string | null
          request_description?: string | null
          requested_at?: string
          requested_by: string
          site_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          equipment_name?: string | null
          farm_name?: string | null
          fixer_description?: string | null
          fixer_name?: string | null
          id?: string
          is_deleted?: boolean
          org_id?: string
          recurring_frequency?: string | null
          request_description?: string | null
          requested_at?: string
          requested_by?: string
          site_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_maint_request_fixer"
            columns: ["fixer_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_maint_request_fixer"
            columns: ["fixer_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_maint_request_requested_by"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_maint_request_requested_by"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "maint_request_equipment_name_fkey"
            columns: ["equipment_name"]
            isOneToOne: false
            referencedRelation: "org_equipment"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "maint_request_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "maint_request_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maint_request_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      maint_request_invnt_item: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          invnt_item_name: string
          is_deleted: boolean
          maint_request_id: string
          org_id: string
          quantity_used: number | null
          uom: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          invnt_item_name: string
          is_deleted?: boolean
          maint_request_id: string
          org_id: string
          quantity_used?: number | null
          uom?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          invnt_item_name?: string
          is_deleted?: boolean
          maint_request_id?: string
          org_id?: string
          quantity_used?: number | null
          uom?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "maint_request_invnt_item_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "maint_request_invnt_item_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "maint_request_invnt_item_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "maint_request_invnt_item_maint_request_id_fkey"
            columns: ["maint_request_id"]
            isOneToOne: false
            referencedRelation: "maint_request"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maint_request_invnt_item_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maint_request_invnt_item_uom_fkey"
            columns: ["uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      maint_request_photo: {
        Row: {
          caption: string | null
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          maint_request_id: string
          org_id: string
          photo_type: string
          photo_url: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          maint_request_id: string
          org_id: string
          photo_type: string
          photo_url: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          maint_request_id?: string
          org_id?: string
          photo_type?: string
          photo_url?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "maint_request_photo_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "maint_request_photo_maint_request_id_fkey"
            columns: ["maint_request_id"]
            isOneToOne: false
            referencedRelation: "maint_request"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maint_request_photo_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_corrective_action_choice: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_corrective_action_choice_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_corrective_action_taken: {
        Row: {
          assigned_to: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          due_date: string | null
          farm_name: string | null
          fsafe_pest_result_id: string | null
          fsafe_result_id: string | null
          id: string
          is_deleted: boolean
          is_resolved: boolean
          notes: string | null
          ops_corrective_action_choice_name: string | null
          ops_template_name: string | null
          ops_template_result_id: string | null
          org_id: string
          other_action: string | null
          result_description: string | null
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          assigned_to?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          farm_name?: string | null
          fsafe_pest_result_id?: string | null
          fsafe_result_id?: string | null
          id?: string
          is_deleted?: boolean
          is_resolved?: boolean
          notes?: string | null
          ops_corrective_action_choice_name?: string | null
          ops_template_name?: string | null
          ops_template_result_id?: string | null
          org_id: string
          other_action?: string | null
          result_description?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          assigned_to?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          farm_name?: string | null
          fsafe_pest_result_id?: string | null
          fsafe_result_id?: string | null
          id?: string
          is_deleted?: boolean
          is_resolved?: boolean
          notes?: string | null
          ops_corrective_action_choice_name?: string | null
          ops_template_name?: string | null
          ops_template_result_id?: string | null
          org_id?: string
          other_action?: string | null
          result_description?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_ops_corrective_action_taken_assigned_to"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_ops_corrective_action_taken_assigned_to"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_ops_corrective_action_taken_verified_by"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_ops_corrective_action_taken_verified_by"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_fsafe_pest_result_id_fkey"
            columns: ["fsafe_pest_result_id"]
            isOneToOne: false
            referencedRelation: "fsafe_pest_result"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_fsafe_result_id_fkey"
            columns: ["fsafe_result_id"]
            isOneToOne: false
            referencedRelation: "fsafe_result"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_ops_corrective_action_choice_n_fkey"
            columns: ["ops_corrective_action_choice_name"]
            isOneToOne: false
            referencedRelation: "ops_corrective_action_choice"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_ops_template_name_fkey"
            columns: ["ops_template_name"]
            isOneToOne: false
            referencedRelation: "ops_template"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_ops_template_result_id_fkey"
            columns: ["ops_template_result_id"]
            isOneToOne: false
            referencedRelation: "ops_template_result"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_corrective_action_taken_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_task: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string | null
          is_deleted: boolean
          name: string
          org_id: string
          qb_account: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          qb_account?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          qb_account?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_task_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_task_schedule: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          hr_employee_name: string
          id: string
          is_deleted: boolean
          ops_task_name: string
          ops_task_tracker_id: string | null
          org_id: string
          start_time: string
          stop_time: string | null
          total_hours: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          hr_employee_name: string
          id?: string
          is_deleted?: boolean
          ops_task_name: string
          ops_task_tracker_id?: string | null
          org_id: string
          start_time: string
          stop_time?: string | null
          total_hours?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          hr_employee_name?: string
          id?: string
          is_deleted?: boolean
          ops_task_name?: string
          ops_task_tracker_id?: string | null
          org_id?: string
          start_time?: string
          stop_time?: string | null
          total_hours?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_task_schedule_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_schedule_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_schedule_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "ops_task_schedule_ops_task_name_fkey"
            columns: ["ops_task_name"]
            isOneToOne: false
            referencedRelation: "ops_task"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_schedule_ops_task_name_fkey"
            columns: ["ops_task_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["task"]
          },
          {
            foreignKeyName: "ops_task_schedule_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_task_schedule_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_task_template: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          ops_task_name: string
          ops_template_name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          ops_task_name: string
          ops_template_name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          ops_task_name?: string
          ops_template_name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_task_template_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_template_ops_task_name_fkey"
            columns: ["ops_task_name"]
            isOneToOne: false
            referencedRelation: "ops_task"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_template_ops_task_name_fkey"
            columns: ["ops_task_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["task"]
          },
          {
            foreignKeyName: "ops_task_template_ops_template_name_fkey"
            columns: ["ops_template_name"]
            isOneToOne: false
            referencedRelation: "ops_template"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_template_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_task_tracker: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_completed: boolean
          is_deleted: boolean
          notes: string | null
          number_of_people: number | null
          ops_task_name: string
          org_id: string
          sales_product_id: string | null
          site_id: string | null
          start_time: string
          stop_time: string | null
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_completed?: boolean
          is_deleted?: boolean
          notes?: string | null
          number_of_people?: number | null
          ops_task_name: string
          org_id: string
          sales_product_id?: string | null
          site_id?: string | null
          start_time: string
          stop_time?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_completed?: boolean
          is_deleted?: boolean
          notes?: string | null
          number_of_people?: number | null
          ops_task_name?: string
          org_id?: string
          sales_product_id?: string | null
          site_id?: string | null
          start_time?: string
          stop_time?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_task_tracker_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_tracker_ops_task_name_fkey"
            columns: ["ops_task_name"]
            isOneToOne: false
            referencedRelation: "ops_task"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_tracker_ops_task_name_fkey"
            columns: ["ops_task_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["task"]
          },
          {
            foreignKeyName: "ops_task_tracker_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_task_tracker_sales_product_id_fkey"
            columns: ["sales_product_id"]
            isOneToOne: false
            referencedRelation: "sales_product"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "ops_task_tracker_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_task_tracker_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_tracker_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
        ]
      }
      ops_template: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          farm_name: string | null
          is_deleted: boolean
          name: string
          org_id: string
          org_module_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          farm_name?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          org_module_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          farm_name?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          org_module_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_template_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_template_org_module_name_fkey"
            columns: ["org_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_display_name"]
          },
          {
            foreignKeyName: "ops_template_org_module_name_fkey"
            columns: ["org_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_id"]
          },
          {
            foreignKeyName: "ops_template_org_module_name_fkey"
            columns: ["org_module_name"]
            isOneToOne: false
            referencedRelation: "org_module"
            referencedColumns: ["name"]
          },
        ]
      }
      ops_template_question: {
        Row: {
          boolean_pass_value: boolean | null
          created_at: string
          created_by: string | null
          display_order: number
          enum_options: Json | null
          enum_pass_options: Json | null
          farm_name: string | null
          id: string
          include_photo: boolean
          is_deleted: boolean
          is_required: boolean
          maximum_value: number | null
          minimum_value: number | null
          ops_corrective_action_choice_ids: Json | null
          ops_template_name: string
          org_id: string
          question_text: string
          response_type: string
          updated_at: string
          updated_by: string | null
          warning_message: string | null
        }
        Insert: {
          boolean_pass_value?: boolean | null
          created_at?: string
          created_by?: string | null
          display_order?: number
          enum_options?: Json | null
          enum_pass_options?: Json | null
          farm_name?: string | null
          id?: string
          include_photo?: boolean
          is_deleted?: boolean
          is_required?: boolean
          maximum_value?: number | null
          minimum_value?: number | null
          ops_corrective_action_choice_ids?: Json | null
          ops_template_name: string
          org_id: string
          question_text: string
          response_type: string
          updated_at?: string
          updated_by?: string | null
          warning_message?: string | null
        }
        Update: {
          boolean_pass_value?: boolean | null
          created_at?: string
          created_by?: string | null
          display_order?: number
          enum_options?: Json | null
          enum_pass_options?: Json | null
          farm_name?: string | null
          id?: string
          include_photo?: boolean
          is_deleted?: boolean
          is_required?: boolean
          maximum_value?: number | null
          minimum_value?: number | null
          ops_corrective_action_choice_ids?: Json | null
          ops_template_name?: string
          org_id?: string
          question_text?: string
          response_type?: string
          updated_at?: string
          updated_by?: string | null
          warning_message?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_template_question_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_question_ops_template_name_fkey"
            columns: ["ops_template_name"]
            isOneToOne: false
            referencedRelation: "ops_template"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_question_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_template_result: {
        Row: {
          created_at: string
          created_by: string | null
          equipment_name: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          ops_task_tracker_id: string
          ops_template_name: string
          ops_template_question_id: string | null
          org_id: string
          response_boolean: boolean | null
          response_enum: string | null
          response_numeric: number | null
          response_text: string | null
          site_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          equipment_name?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id: string
          ops_template_name: string
          ops_template_question_id?: string | null
          org_id: string
          response_boolean?: boolean | null
          response_enum?: string | null
          response_numeric?: number | null
          response_text?: string | null
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          equipment_name?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          ops_task_tracker_id?: string
          ops_template_name?: string
          ops_template_question_id?: string | null
          org_id?: string
          response_boolean?: boolean | null
          response_enum?: string | null
          response_numeric?: number | null
          response_text?: string | null
          site_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_template_result_equipment_name_fkey"
            columns: ["equipment_name"]
            isOneToOne: false
            referencedRelation: "org_equipment"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_result_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_template_result_ops_template_name_fkey"
            columns: ["ops_template_name"]
            isOneToOne: false
            referencedRelation: "ops_template"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_result_ops_template_question_id_fkey"
            columns: ["ops_template_question_id"]
            isOneToOne: false
            referencedRelation: "ops_template_question"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_template_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_template_result_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_template_result_photo: {
        Row: {
          caption: string | null
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          ops_template_result_id: string
          org_id: string
          photo_url: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          ops_template_result_id: string
          org_id: string
          photo_url: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          ops_template_result_id?: string
          org_id?: string
          photo_url?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_template_result_photo_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_template_result_photo_ops_template_result_id_fkey"
            columns: ["ops_template_result_id"]
            isOneToOne: false
            referencedRelation: "ops_template_result"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_template_result_photo_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_training: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          materials_url: string | null
          notes: string | null
          ops_training_type_name: string | null
          org_id: string
          topics_covered: Json
          trainer_name: string | null
          training_date: string | null
          updated_at: string
          updated_by: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          materials_url?: string | null
          notes?: string | null
          ops_training_type_name?: string | null
          org_id: string
          topics_covered?: Json
          trainer_name?: string | null
          training_date?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          materials_url?: string | null
          notes?: string | null
          ops_training_type_name?: string | null
          org_id?: string
          topics_covered?: Json
          trainer_name?: string | null
          training_date?: string | null
          updated_at?: string
          updated_by?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_ops_training_trainer"
            columns: ["trainer_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_ops_training_trainer"
            columns: ["trainer_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_ops_training_verified_by"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_ops_training_verified_by"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "ops_training_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_training_ops_training_type_name_fkey"
            columns: ["ops_training_type_name"]
            isOneToOne: false
            referencedRelation: "ops_training_type"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_training_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_training_attendee: {
        Row: {
          certificate_issuer: string | null
          certificate_url: string | null
          certification_expires_on: string | null
          certification_issued_on: string | null
          certification_number: string | null
          created_at: string
          created_by: string | null
          farm_name: string | null
          hr_employee_name: string
          id: string
          is_deleted: boolean
          notes: string | null
          ops_training_id: string
          org_id: string
          signed_at: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          certificate_issuer?: string | null
          certificate_url?: string | null
          certification_expires_on?: string | null
          certification_issued_on?: string | null
          certification_number?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          hr_employee_name: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          ops_training_id: string
          org_id: string
          signed_at?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          certificate_issuer?: string | null
          certificate_url?: string | null
          certification_expires_on?: string | null
          certification_issued_on?: string | null
          certification_number?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          hr_employee_name?: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          ops_training_id?: string
          org_id?: string
          signed_at?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_training_attendee_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_training_attendee_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_training_attendee_hr_employee_name_fkey"
            columns: ["hr_employee_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "ops_training_attendee_ops_training_id_fkey"
            columns: ["ops_training_id"]
            isOneToOne: false
            referencedRelation: "ops_training"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ops_training_attendee_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_training_type: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ops_training_type_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org: {
        Row: {
          address: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          id: string
          is_deleted: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          id: string
          is_deleted?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          id?: string
          is_deleted?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      org_business_rule: {
        Row: {
          applies_to: Json
          created_at: string
          created_by: string | null
          description: string
          display_order: number
          id: string
          is_active: boolean
          is_deleted: boolean
          module: string | null
          org_id: string
          rationale: string | null
          rule_type: string
          title: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          applies_to?: Json
          created_at?: string
          created_by?: string | null
          description: string
          display_order?: number
          id: string
          is_active?: boolean
          is_deleted?: boolean
          module?: string | null
          org_id: string
          rationale?: string | null
          rule_type: string
          title: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          applies_to?: Json
          created_at?: string
          created_by?: string | null
          description?: string
          display_order?: number
          id?: string
          is_active?: boolean
          is_deleted?: boolean
          module?: string | null
          org_id?: string
          rationale?: string | null
          rule_type?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_business_rule_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org_equipment: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          farm_name: string | null
          is_deleted: boolean
          manual_url: string | null
          manufacturer: string | null
          model: string | null
          name: string
          org_id: string
          purchase_date: string | null
          serial_number: string | null
          type: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string | null
          is_deleted?: boolean
          manual_url?: string | null
          manufacturer?: string | null
          model?: string | null
          name: string
          org_id: string
          purchase_date?: string | null
          serial_number?: string | null
          type?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          farm_name?: string | null
          is_deleted?: boolean
          manual_url?: string | null
          manufacturer?: string | null
          model?: string | null
          name?: string
          org_id?: string
          purchase_date?: string | null
          serial_number?: string | null
          type?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_equipment_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_equipment_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org_farm: {
        Row: {
          created_at: string
          created_by: string | null
          growing_uom: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
          volume_uom: string | null
          weighing_uom: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          growing_uom?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
          volume_uom?: string | null
          weighing_uom?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          growing_uom?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
          volume_uom?: string | null
          weighing_uom?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_farm_growing_uom_fkey"
            columns: ["growing_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "org_farm_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_farm_volume_uom_fkey"
            columns: ["volume_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "org_farm_weighing_uom_fkey"
            columns: ["weighing_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      org_module: {
        Row: {
          created_at: string
          created_by: string | null
          display_order: number
          is_deleted: boolean
          is_enabled: boolean
          name: string
          org_id: string
          sys_module_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          is_deleted?: boolean
          is_enabled?: boolean
          name: string
          org_id: string
          sys_module_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          is_deleted?: boolean
          is_enabled?: boolean
          name?: string
          org_id?: string
          sys_module_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_module_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_module_sys_module_name_fkey"
            columns: ["sys_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_slug"]
          },
          {
            foreignKeyName: "org_module_sys_module_name_fkey"
            columns: ["sys_module_name"]
            isOneToOne: false
            referencedRelation: "sys_module"
            referencedColumns: ["name"]
          },
        ]
      }
      org_site: {
        Row: {
          acres: number | null
          created_at: string
          created_by: string | null
          display_order: number
          elevation: number | null
          farm_name: string | null
          id: string
          is_active: boolean
          is_deleted: boolean
          latitude: number | null
          longitude: number | null
          monitoring_stations: Json
          name: string
          notes: string | null
          org_id: string
          org_site_category_id: string
          org_site_subcategory_id: string | null
          site_id_parent: string | null
          updated_at: string
          updated_by: string | null
          zone: string | null
        }
        Insert: {
          acres?: number | null
          created_at?: string
          created_by?: string | null
          display_order?: number
          elevation?: number | null
          farm_name?: string | null
          id: string
          is_active?: boolean
          is_deleted?: boolean
          latitude?: number | null
          longitude?: number | null
          monitoring_stations?: Json
          name: string
          notes?: string | null
          org_id: string
          org_site_category_id: string
          org_site_subcategory_id?: string | null
          site_id_parent?: string | null
          updated_at?: string
          updated_by?: string | null
          zone?: string | null
        }
        Update: {
          acres?: number | null
          created_at?: string
          created_by?: string | null
          display_order?: number
          elevation?: number | null
          farm_name?: string | null
          id?: string
          is_active?: boolean
          is_deleted?: boolean
          latitude?: number | null
          longitude?: number | null
          monitoring_stations?: Json
          name?: string
          notes?: string | null
          org_id?: string
          org_site_category_id?: string
          org_site_subcategory_id?: string | null
          site_id_parent?: string | null
          updated_at?: string
          updated_by?: string | null
          zone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_org_site_category"
            columns: ["org_site_category_id"]
            isOneToOne: false
            referencedRelation: "org_site_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_org_site_subcategory"
            columns: ["org_site_subcategory_id"]
            isOneToOne: false
            referencedRelation: "org_site_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_site_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_site_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_site_site_id_parent_fkey"
            columns: ["site_id_parent"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      org_site_category: {
        Row: {
          category_name: string
          created_at: string
          created_by: string | null
          display_order: number
          id: string
          is_deleted: boolean
          org_id: string
          sub_category_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          category_name: string
          created_at?: string
          created_by?: string | null
          display_order?: number
          id: string
          is_deleted?: boolean
          org_id: string
          sub_category_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          category_name?: string
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          is_deleted?: boolean
          org_id?: string
          sub_category_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_site_category_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org_site_cuke_gh: {
        Row: {
          acres: number | null
          blocks_vertical: boolean
          created_at: string
          created_by: string | null
          farm_name: string
          farm_section: string
          id: string
          is_deleted: boolean
          layout_grid_col: number
          layout_grid_row: number
          layout_stack_pos: number | null
          org_id: string
          rows_orientation: string
          sidewalk_position: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          acres?: number | null
          blocks_vertical?: boolean
          created_at?: string
          created_by?: string | null
          farm_name: string
          farm_section: string
          id: string
          is_deleted?: boolean
          layout_grid_col: number
          layout_grid_row: number
          layout_stack_pos?: number | null
          org_id: string
          rows_orientation: string
          sidewalk_position: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          acres?: number | null
          blocks_vertical?: boolean
          created_at?: string
          created_by?: string | null
          farm_name?: string
          farm_section?: string
          id?: string
          is_deleted?: boolean
          layout_grid_col?: number
          layout_grid_row?: number
          layout_stack_pos?: number | null
          org_id?: string
          rows_orientation?: string
          sidewalk_position?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_site_cuke_gh_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_site_cuke_gh_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org_site_cuke_gh_block: {
        Row: {
          block_number: number
          created_at: string
          created_by: string | null
          direction: string
          farm_name: string
          id: string
          is_deleted: boolean
          name: string
          org_id: string
          row_number_from: number
          row_number_to: number
          site_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          block_number: number
          created_at?: string
          created_by?: string | null
          direction: string
          farm_name: string
          id?: string
          is_deleted?: boolean
          name: string
          org_id: string
          row_number_from: number
          row_number_to: number
          site_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          block_number?: number
          created_at?: string
          created_by?: string | null
          direction?: string
          farm_name?: string
          id?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          row_number_from?: number
          row_number_to?: number
          site_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_site_cuke_gh_block_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_site_cuke_gh_block_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_site_cuke_gh_block_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site_cuke_gh"
            referencedColumns: ["id"]
          },
        ]
      }
      org_site_cuke_gh_row: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          row_number: number
          site_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          row_number: number
          site_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          row_number?: number
          site_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_site_cuke_gh_row_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_site_cuke_gh_row_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_site_cuke_gh_row_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site_cuke_gh"
            referencedColumns: ["id"]
          },
        ]
      }
      org_site_housing: {
        Row: {
          address: string | null
          created_at: string
          created_by: string | null
          is_deleted: boolean
          maximum_beds: number | null
          name: string
          notes: string | null
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          maximum_beds?: number | null
          name: string
          notes?: string | null
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          maximum_beds?: number | null
          name?: string
          notes?: string | null
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_site_housing_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org_site_housing_area: {
        Row: {
          created_at: string
          created_by: string | null
          housing_name: string
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          housing_name: string
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          housing_name?: string
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_site_housing_area_housing_name_fkey"
            columns: ["housing_name"]
            isOneToOne: false
            referencedRelation: "org_site_housing"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_site_housing_area_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      org_sub_module: {
        Row: {
          created_at: string
          created_by: string | null
          display_order: number
          is_deleted: boolean
          is_enabled: boolean
          name: string
          org_id: string
          sys_access_level_name: string
          sys_module_name: string
          sys_sub_module_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          is_deleted?: boolean
          is_enabled?: boolean
          name: string
          org_id: string
          sys_access_level_name: string
          sys_module_name: string
          sys_sub_module_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          is_deleted?: boolean
          is_enabled?: boolean
          name?: string
          org_id?: string
          sys_access_level_name?: string
          sys_module_name?: string
          sys_sub_module_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_sub_module_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_sub_module_sys_access_level_name_fkey"
            columns: ["sys_access_level_name"]
            isOneToOne: false
            referencedRelation: "sys_access_level"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_sub_module_sys_module_name_fkey"
            columns: ["sys_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_slug"]
          },
          {
            foreignKeyName: "org_sub_module_sys_module_name_fkey"
            columns: ["sys_module_name"]
            isOneToOne: false
            referencedRelation: "sys_module"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "org_sub_module_sys_sub_module_name_fkey"
            columns: ["sys_sub_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["sub_module_slug"]
          },
          {
            foreignKeyName: "org_sub_module_sys_sub_module_name_fkey"
            columns: ["sys_sub_module_name"]
            isOneToOne: false
            referencedRelation: "sys_sub_module"
            referencedColumns: ["name"]
          },
        ]
      }
      pack_dryer_result: {
        Row: {
          belt_speed: number | null
          check_at: string
          created_at: string
          created_by: string | null
          dryer_temperature: number | null
          farm_name: string
          greenhouse_temperature: number | null
          grow_lettuce_seed_batch_id: string | null
          id: string
          invnt_item_name: string | null
          is_deleted: boolean
          moisture_after_dryer: number | null
          moisture_before_dryer: number | null
          moisture_uom: string
          notes: string | null
          org_id: string
          pack_dryer_result_id_original: string | null
          packhouse_temperature: number | null
          pre_packing_leaf_temperature: number | null
          site_id: string
          temperature_uom: string
          tracking_code: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          belt_speed?: number | null
          check_at: string
          created_at?: string
          created_by?: string | null
          dryer_temperature?: number | null
          farm_name: string
          greenhouse_temperature?: number | null
          grow_lettuce_seed_batch_id?: string | null
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          moisture_after_dryer?: number | null
          moisture_before_dryer?: number | null
          moisture_uom: string
          notes?: string | null
          org_id: string
          pack_dryer_result_id_original?: string | null
          packhouse_temperature?: number | null
          pre_packing_leaf_temperature?: number | null
          site_id: string
          temperature_uom: string
          tracking_code?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          belt_speed?: number | null
          check_at?: string
          created_at?: string
          created_by?: string | null
          dryer_temperature?: number | null
          farm_name?: string
          greenhouse_temperature?: number | null
          grow_lettuce_seed_batch_id?: string | null
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          moisture_after_dryer?: number | null
          moisture_before_dryer?: number | null
          moisture_uom?: string
          notes?: string | null
          org_id?: string
          pack_dryer_result_id_original?: string | null
          packhouse_temperature?: number | null
          pre_packing_leaf_temperature?: number | null
          site_id?: string
          temperature_uom?: string
          tracking_code?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_dryer_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_dryer_result_grow_lettuce_seed_batch_id_fkey"
            columns: ["grow_lettuce_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_lettuce_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_dryer_result_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_dryer_result_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "pack_dryer_result_moisture_uom_fkey"
            columns: ["moisture_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "pack_dryer_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_dryer_result_pack_dryer_result_id_original_fkey"
            columns: ["pack_dryer_result_id_original"]
            isOneToOne: false
            referencedRelation: "pack_dryer_result"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_dryer_result_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_dryer_result_temperature_uom_fkey"
            columns: ["temperature_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      pack_lot: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          harvest_date: string | null
          id: string
          is_deleted: boolean
          lot_number: string
          org_id: string
          pack_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          harvest_date?: string | null
          id?: string
          is_deleted?: boolean
          lot_number: string
          org_id: string
          pack_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          harvest_date?: string | null
          id?: string
          is_deleted?: boolean
          lot_number?: string
          org_id?: string
          pack_date?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_lot_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_lot_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_lot_item: {
        Row: {
          best_by_date: string
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          is_deleted: boolean
          org_id: string
          pack_lot_id: string
          pack_quantity: number
          sales_product_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          best_by_date: string
          created_at?: string
          created_by?: string | null
          farm_name: string
          id?: string
          is_deleted?: boolean
          org_id: string
          pack_lot_id: string
          pack_quantity: number
          sales_product_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          best_by_date?: string
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          is_deleted?: boolean
          org_id?: string
          pack_lot_id?: string
          pack_quantity?: number
          sales_product_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_lot_item_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_lot_item_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_lot_item_pack_lot_id_fkey"
            columns: ["pack_lot_id"]
            isOneToOne: false
            referencedRelation: "pack_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_lot_item_sales_product_id_fkey"
            columns: ["sales_product_id"]
            isOneToOne: false
            referencedRelation: "sales_product"
            referencedColumns: ["code"]
          },
        ]
      }
      pack_productivity_fail_category: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          farm_name: string | null
          is_active: boolean
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          farm_name?: string | null
          is_active?: boolean
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          farm_name?: string | null
          is_active?: boolean
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_productivity_fail_category_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_productivity_fail_category_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_productivity_hour: {
        Row: {
          boxers: number
          cases_packed: number
          catchers: number
          created_at: string
          created_by: string | null
          farm_name: string
          fsafe_metal_detected_at: string | null
          id: string
          is_deleted: boolean
          leftover_pounds: number
          mixers: number
          notes: string | null
          ops_task_tracker_id: string
          org_id: string
          pack_end_hour: string
          packers: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          boxers?: number
          cases_packed?: number
          catchers?: number
          created_at?: string
          created_by?: string | null
          farm_name: string
          fsafe_metal_detected_at?: string | null
          id?: string
          is_deleted?: boolean
          leftover_pounds?: number
          mixers?: number
          notes?: string | null
          ops_task_tracker_id: string
          org_id: string
          pack_end_hour: string
          packers?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          boxers?: number
          cases_packed?: number
          catchers?: number
          created_at?: string
          created_by?: string | null
          farm_name?: string
          fsafe_metal_detected_at?: string | null
          id?: string
          is_deleted?: boolean
          leftover_pounds?: number
          mixers?: number
          notes?: string | null
          ops_task_tracker_id?: string
          org_id?: string
          pack_end_hour?: string
          packers?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_productivity_hour_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_productivity_hour_ops_task_tracker_id_fkey"
            columns: ["ops_task_tracker_id"]
            isOneToOne: false
            referencedRelation: "ops_task_tracker"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_productivity_hour_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_productivity_hour_fail: {
        Row: {
          created_at: string
          created_by: string | null
          fail_count: number
          farm_name: string
          id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          pack_productivity_fail_category_name: string
          pack_productivity_hour_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          fail_count?: number
          farm_name: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          pack_productivity_fail_category_name: string
          pack_productivity_hour_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          fail_count?: number
          farm_name?: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          pack_productivity_fail_category_name?: string
          pack_productivity_hour_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_productivity_hour_fail_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_productivity_hour_fail_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_productivity_hour_fail_pack_productivity_fail_categor_fkey"
            columns: ["pack_productivity_fail_category_name"]
            isOneToOne: false
            referencedRelation: "pack_productivity_fail_category"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_productivity_hour_fail_pack_productivity_hour_id_fkey"
            columns: ["pack_productivity_hour_id"]
            isOneToOne: false
            referencedRelation: "pack_productivity_hour"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_shelf_life: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          invnt_item_name: string | null
          is_deleted: boolean
          is_terminated: boolean
          notes: string | null
          org_id: string
          pack_lot_id: string | null
          sales_product_id: string | null
          site_id: string | null
          target_shelf_life_days: number | null
          termination_reason: string | null
          trial_number: number | null
          trial_purpose: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          is_terminated?: boolean
          notes?: string | null
          org_id: string
          pack_lot_id?: string | null
          sales_product_id?: string | null
          site_id?: string | null
          target_shelf_life_days?: number | null
          termination_reason?: string | null
          trial_number?: number | null
          trial_purpose?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          invnt_item_name?: string | null
          is_deleted?: boolean
          is_terminated?: boolean
          notes?: string | null
          org_id?: string
          pack_lot_id?: string | null
          sales_product_id?: string | null
          site_id?: string | null
          target_shelf_life_days?: number | null
          termination_reason?: string | null
          trial_number?: number | null
          trial_purpose?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_shelf_life_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_shelf_life_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_shelf_life_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "pack_shelf_life_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_shelf_life_pack_lot_id_fkey"
            columns: ["pack_lot_id"]
            isOneToOne: false
            referencedRelation: "pack_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_shelf_life_sales_product_id_fkey"
            columns: ["sales_product_id"]
            isOneToOne: false
            referencedRelation: "sales_product"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "pack_shelf_life_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_shelf_life_metric: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          enum_options: Json | null
          fail_boolean: boolean | null
          fail_enum_values: Json | null
          fail_maximum_value: number | null
          fail_minimum_value: number | null
          farm_name: string | null
          is_active: boolean
          is_deleted: boolean
          name: string
          org_id: string
          response_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          enum_options?: Json | null
          fail_boolean?: boolean | null
          fail_enum_values?: Json | null
          fail_maximum_value?: number | null
          fail_minimum_value?: number | null
          farm_name?: string | null
          is_active?: boolean
          is_deleted?: boolean
          name: string
          org_id: string
          response_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          enum_options?: Json | null
          fail_boolean?: boolean | null
          fail_enum_values?: Json | null
          fail_maximum_value?: number | null
          fail_minimum_value?: number | null
          farm_name?: string | null
          is_active?: boolean
          is_deleted?: boolean
          name?: string
          org_id?: string
          response_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_shelf_life_metric_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_shelf_life_metric_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_shelf_life_photo: {
        Row: {
          caption: string | null
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          observation_date: string
          org_id: string
          pack_shelf_life_id: string
          photo_url: string
          shelf_life_day: number
          side: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          observation_date: string
          org_id: string
          pack_shelf_life_id: string
          photo_url: string
          shelf_life_day: number
          side: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          observation_date?: string
          org_id?: string
          pack_shelf_life_id?: string
          photo_url?: string
          shelf_life_day?: number
          side?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_shelf_life_photo_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_shelf_life_photo_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_shelf_life_photo_pack_shelf_life_id_fkey"
            columns: ["pack_shelf_life_id"]
            isOneToOne: false
            referencedRelation: "pack_shelf_life"
            referencedColumns: ["id"]
          },
        ]
      }
      pack_shelf_life_result: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string | null
          id: string
          is_deleted: boolean
          notes: string | null
          observation_date: string
          org_id: string
          pack_shelf_life_id: string
          pack_shelf_life_metric_name: string
          response_boolean: boolean | null
          response_enum: string | null
          response_numeric: number | null
          response_text: string | null
          shelf_life_day: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          observation_date: string
          org_id: string
          pack_shelf_life_id: string
          pack_shelf_life_metric_name: string
          response_boolean?: boolean | null
          response_enum?: string | null
          response_numeric?: number | null
          response_text?: string | null
          shelf_life_day: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          observation_date?: string
          org_id?: string
          pack_shelf_life_id?: string
          pack_shelf_life_metric_name?: string
          response_boolean?: boolean | null
          response_enum?: string | null
          response_numeric?: number | null
          response_text?: string | null
          shelf_life_day?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pack_shelf_life_result_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "pack_shelf_life_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_shelf_life_result_pack_shelf_life_id_fkey"
            columns: ["pack_shelf_life_id"]
            isOneToOne: false
            referencedRelation: "pack_shelf_life"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pack_shelf_life_result_pack_shelf_life_metric_name_fkey"
            columns: ["pack_shelf_life_metric_name"]
            isOneToOne: false
            referencedRelation: "pack_shelf_life_metric"
            referencedColumns: ["name"]
          },
        ]
      }
      sales_container_type: {
        Row: {
          created_at: string
          created_by: string | null
          is_active: boolean
          is_deleted: boolean
          maximum_spaces: number
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          is_active?: boolean
          is_deleted?: boolean
          maximum_spaces: number
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          is_active?: boolean
          is_deleted?: boolean
          maximum_spaces?: number
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_container_type_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_crm_external_product: {
        Row: {
          created_at: string
          created_by: string | null
          display_order: number
          is_active: boolean
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          is_active?: boolean
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_order?: number
          is_active?: boolean
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_crm_external_product_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_crm_store: {
        Row: {
          chain: string | null
          contact_email: string | null
          contact_name: string | null
          contact_phone: string | null
          contact_title: string | null
          created_at: string
          created_by: string | null
          is_active: boolean
          is_deleted: boolean
          island: string | null
          location: string | null
          name: string
          org_id: string
          sales_customer_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          chain?: string | null
          contact_email?: string | null
          contact_name?: string | null
          contact_phone?: string | null
          contact_title?: string | null
          created_at?: string
          created_by?: string | null
          is_active?: boolean
          is_deleted?: boolean
          island?: string | null
          location?: string | null
          name: string
          org_id: string
          sales_customer_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          chain?: string | null
          contact_email?: string | null
          contact_name?: string | null
          contact_phone?: string | null
          contact_title?: string | null
          created_at?: string
          created_by?: string | null
          is_active?: boolean
          is_deleted?: boolean
          island?: string | null
          location?: string | null
          name?: string
          org_id?: string
          sales_customer_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_crm_store_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_crm_store_sales_customer_name_fkey"
            columns: ["sales_customer_name"]
            isOneToOne: false
            referencedRelation: "sales_customer"
            referencedColumns: ["name"]
          },
        ]
      }
      sales_crm_store_visit: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          sales_crm_store_name: string
          updated_at: string
          updated_by: string | null
          visit_date: string
          visited_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          sales_crm_store_name: string
          updated_at?: string
          updated_by?: string | null
          visit_date: string
          visited_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          sales_crm_store_name?: string
          updated_at?: string
          updated_by?: string | null
          visit_date?: string
          visited_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_crm_store_visit_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_sales_crm_store_name_fkey"
            columns: ["sales_crm_store_name"]
            isOneToOne: false
            referencedRelation: "sales_crm_store"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_visited_by_fkey"
            columns: ["visited_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_visited_by_fkey"
            columns: ["visited_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
        ]
      }
      sales_crm_store_visit_photo: {
        Row: {
          caption: string | null
          created_at: string
          created_by: string | null
          id: string
          is_deleted: boolean
          org_id: string
          photo_url: string
          sales_crm_store_visit_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          org_id: string
          photo_url: string
          sales_crm_store_visit_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          org_id?: string
          photo_url?: string
          sales_crm_store_visit_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_crm_store_visit_photo_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_photo_sales_crm_store_visit_id_fkey"
            columns: ["sales_crm_store_visit_id"]
            isOneToOne: false
            referencedRelation: "sales_crm_store_visit"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_crm_store_visit_result: {
        Row: {
          best_by_date: string | null
          cases_per_week: number | null
          created_at: string
          created_by: string | null
          id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          sales_crm_external_product_name: string | null
          sales_crm_store_visit_id: string
          sales_product_id: string | null
          shelf_price: number | null
          stock_level: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          best_by_date?: string | null
          cases_per_week?: number | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          sales_crm_external_product_name?: string | null
          sales_crm_store_visit_id: string
          sales_product_id?: string | null
          shelf_price?: number | null
          stock_level?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          best_by_date?: string | null
          cases_per_week?: number | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          sales_crm_external_product_name?: string | null
          sales_crm_store_visit_id?: string
          sales_product_id?: string | null
          shelf_price?: number | null
          stock_level?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_crm_store_visit_result_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_result_sales_crm_external_product_na_fkey"
            columns: ["sales_crm_external_product_name"]
            isOneToOne: false
            referencedRelation: "sales_crm_external_product"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_result_sales_crm_store_visit_id_fkey"
            columns: ["sales_crm_store_visit_id"]
            isOneToOne: false
            referencedRelation: "sales_crm_store_visit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_crm_store_visit_result_sales_product_id_fkey"
            columns: ["sales_product_id"]
            isOneToOne: false
            referencedRelation: "sales_product"
            referencedColumns: ["code"]
          },
        ]
      }
      sales_customer: {
        Row: {
          billing_address: string | null
          cc_emails: Json
          created_at: string
          created_by: string | null
          email: string | null
          is_active: boolean
          is_deleted: boolean
          name: string
          org_id: string
          qb_account: string | null
          sales_customer_group_name: string | null
          sales_fob_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          billing_address?: string | null
          cc_emails?: Json
          created_at?: string
          created_by?: string | null
          email?: string | null
          is_active?: boolean
          is_deleted?: boolean
          name: string
          org_id: string
          qb_account?: string | null
          sales_customer_group_name?: string | null
          sales_fob_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          billing_address?: string | null
          cc_emails?: Json
          created_at?: string
          created_by?: string | null
          email?: string | null
          is_active?: boolean
          is_deleted?: boolean
          name?: string
          org_id?: string
          qb_account?: string | null
          sales_customer_group_name?: string | null
          sales_fob_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_customer_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_customer_sales_customer_group_name_fkey"
            columns: ["sales_customer_group_name"]
            isOneToOne: false
            referencedRelation: "sales_customer_group"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_customer_sales_fob_name_fkey"
            columns: ["sales_fob_name"]
            isOneToOne: false
            referencedRelation: "sales_fob"
            referencedColumns: ["name"]
          },
        ]
      }
      sales_customer_group: {
        Row: {
          created_at: string
          created_by: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_customer_group_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_fob: {
        Row: {
          created_at: string
          created_by: string | null
          is_deleted: boolean
          name: string
          org_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          name: string
          org_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          name?: string
          org_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_fob_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_invoice: {
        Row: {
          cases: number | null
          created_at: string
          created_by: string | null
          customer_group: string | null
          customer_name: string
          dollars: number
          farm_name: string | null
          grade: string | null
          id: string
          invoice_date: string
          invoice_number: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          pounds: number | null
          product_code: string | null
          updated_at: string
          updated_by: string | null
          variety: string | null
        }
        Insert: {
          cases?: number | null
          created_at?: string
          created_by?: string | null
          customer_group?: string | null
          customer_name: string
          dollars: number
          farm_name?: string | null
          grade?: string | null
          id?: string
          invoice_date: string
          invoice_number: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          pounds?: number | null
          product_code?: string | null
          updated_at?: string
          updated_by?: string | null
          variety?: string | null
        }
        Update: {
          cases?: number | null
          created_at?: string
          created_by?: string | null
          customer_group?: string | null
          customer_name?: string
          dollars?: number
          farm_name?: string | null
          grade?: string | null
          id?: string
          invoice_date?: string
          invoice_number?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          pounds?: number | null
          product_code?: string | null
          updated_at?: string
          updated_by?: string | null
          variety?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoice_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_invoice_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_po: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string | null
          id: string
          invoice_date: string | null
          is_deleted: boolean
          notes: string | null
          order_date: string
          org_id: string
          po_number: string | null
          qb_uploaded_at: string | null
          qb_uploaded_by: string | null
          recurring_frequency: string | null
          sales_customer_group_name: string | null
          sales_customer_name: string
          sales_fob_name: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          invoice_date?: string | null
          is_deleted?: boolean
          notes?: string | null
          order_date: string
          org_id: string
          po_number?: string | null
          qb_uploaded_at?: string | null
          qb_uploaded_by?: string | null
          recurring_frequency?: string | null
          sales_customer_group_name?: string | null
          sales_customer_name: string
          sales_fob_name?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          invoice_date?: string | null
          is_deleted?: boolean
          notes?: string | null
          order_date?: string
          org_id?: string
          po_number?: string | null
          qb_uploaded_at?: string | null
          qb_uploaded_by?: string | null
          recurring_frequency?: string | null
          sales_customer_group_name?: string | null
          sales_customer_name?: string
          sales_fob_name?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_sales_po_approved_by"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_sales_po_approved_by"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "fk_sales_po_qb_uploaded_by"
            columns: ["qb_uploaded_by"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_sales_po_qb_uploaded_by"
            columns: ["qb_uploaded_by"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
          {
            foreignKeyName: "sales_po_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_po_sales_customer_group_name_fkey"
            columns: ["sales_customer_group_name"]
            isOneToOne: false
            referencedRelation: "sales_customer_group"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_po_sales_customer_name_fkey"
            columns: ["sales_customer_name"]
            isOneToOne: false
            referencedRelation: "sales_customer"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_po_sales_fob_name_fkey"
            columns: ["sales_fob_name"]
            isOneToOne: false
            referencedRelation: "sales_fob"
            referencedColumns: ["name"]
          },
        ]
      }
      sales_po_fulfillment: {
        Row: {
          booking_id: string | null
          container_id: string | null
          container_space: string | null
          created_at: string
          created_by: string | null
          farm_name: string
          fulfilled_quantity: number
          id: string
          is_deleted: boolean
          notes: string | null
          org_id: string
          pack_lot_id: string | null
          pallet_number: string | null
          sales_container_type_name: string | null
          sales_po_id: string
          sales_po_line_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          booking_id?: string | null
          container_id?: string | null
          container_space?: string | null
          created_at?: string
          created_by?: string | null
          farm_name: string
          fulfilled_quantity: number
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id: string
          pack_lot_id?: string | null
          pallet_number?: string | null
          sales_container_type_name?: string | null
          sales_po_id: string
          sales_po_line_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          booking_id?: string | null
          container_id?: string | null
          container_space?: string | null
          created_at?: string
          created_by?: string | null
          farm_name?: string
          fulfilled_quantity?: number
          id?: string
          is_deleted?: boolean
          notes?: string | null
          org_id?: string
          pack_lot_id?: string | null
          pallet_number?: string | null
          sales_container_type_name?: string | null
          sales_po_id?: string
          sales_po_line_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_po_fulfillment_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_po_fulfillment_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_po_fulfillment_pack_lot_id_fkey"
            columns: ["pack_lot_id"]
            isOneToOne: false
            referencedRelation: "pack_lot"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_po_fulfillment_sales_container_type_name_fkey"
            columns: ["sales_container_type_name"]
            isOneToOne: false
            referencedRelation: "sales_container_type"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_po_fulfillment_sales_po_id_fkey"
            columns: ["sales_po_id"]
            isOneToOne: false
            referencedRelation: "sales_po"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_po_fulfillment_sales_po_line_id_fkey"
            columns: ["sales_po_line_id"]
            isOneToOne: false
            referencedRelation: "sales_po_line"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_po_line: {
        Row: {
          created_at: string
          created_by: string | null
          farm_name: string
          id: string
          is_deleted: boolean
          notes: string | null
          order_quantity: number
          org_id: string
          price_per_case: number
          sales_po_id: string
          sales_product_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          farm_name: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          order_quantity: number
          org_id: string
          price_per_case: number
          sales_po_id: string
          sales_product_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          farm_name?: string
          id?: string
          is_deleted?: boolean
          notes?: string | null
          order_quantity?: number
          org_id?: string
          price_per_case?: number
          sales_po_id?: string
          sales_product_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_po_line_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_po_line_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_po_line_sales_po_id_fkey"
            columns: ["sales_po_id"]
            isOneToOne: false
            referencedRelation: "sales_po"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_po_line_sales_product_id_fkey"
            columns: ["sales_product_id"]
            isOneToOne: false
            referencedRelation: "sales_product"
            referencedColumns: ["code"]
          },
        ]
      }
      sales_product: {
        Row: {
          case_height: number | null
          case_length: number | null
          case_net_weight: number | null
          case_width: number | null
          code: string
          created_at: string
          created_by: string | null
          description: string | null
          dimension_uom: string | null
          display_order: number
          farm_name: string
          grow_grade_id: string | null
          gtin: string | null
          invnt_item_name: string | null
          is_active: boolean
          is_catch_weight: boolean
          is_deleted: boolean
          is_fsma_traceable: boolean
          is_hazardous: boolean
          item_per_pack: number | null
          item_uom: string | null
          manufacturer_storage_method: string | null
          maximum_case_per_pallet: number | null
          maximum_storage_temperature: number | null
          minimum_storage_temperature: number | null
          name: string
          org_id: string
          pack_net_weight: number | null
          pack_per_case: number | null
          pack_uom: string | null
          pallet_hi: number | null
          pallet_net_weight: number | null
          pallet_ti: number | null
          photos: Json
          shelf_life_days: number | null
          shipping_requirements: string | null
          temperature_uom: string | null
          upc: string | null
          updated_at: string
          updated_by: string | null
          weight_uom: string | null
        }
        Insert: {
          case_height?: number | null
          case_length?: number | null
          case_net_weight?: number | null
          case_width?: number | null
          code: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          dimension_uom?: string | null
          display_order?: number
          farm_name: string
          grow_grade_id?: string | null
          gtin?: string | null
          invnt_item_name?: string | null
          is_active?: boolean
          is_catch_weight?: boolean
          is_deleted?: boolean
          is_fsma_traceable?: boolean
          is_hazardous?: boolean
          item_per_pack?: number | null
          item_uom?: string | null
          manufacturer_storage_method?: string | null
          maximum_case_per_pallet?: number | null
          maximum_storage_temperature?: number | null
          minimum_storage_temperature?: number | null
          name: string
          org_id: string
          pack_net_weight?: number | null
          pack_per_case?: number | null
          pack_uom?: string | null
          pallet_hi?: number | null
          pallet_net_weight?: number | null
          pallet_ti?: number | null
          photos?: Json
          shelf_life_days?: number | null
          shipping_requirements?: string | null
          temperature_uom?: string | null
          upc?: string | null
          updated_at?: string
          updated_by?: string | null
          weight_uom?: string | null
        }
        Update: {
          case_height?: number | null
          case_length?: number | null
          case_net_weight?: number | null
          case_width?: number | null
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          dimension_uom?: string | null
          display_order?: number
          farm_name?: string
          grow_grade_id?: string | null
          gtin?: string | null
          invnt_item_name?: string | null
          is_active?: boolean
          is_catch_weight?: boolean
          is_deleted?: boolean
          is_fsma_traceable?: boolean
          is_hazardous?: boolean
          item_per_pack?: number | null
          item_uom?: string | null
          manufacturer_storage_method?: string | null
          maximum_case_per_pallet?: number | null
          maximum_storage_temperature?: number | null
          minimum_storage_temperature?: number | null
          name?: string
          org_id?: string
          pack_net_weight?: number | null
          pack_per_case?: number | null
          pack_uom?: string | null
          pallet_hi?: number | null
          pallet_net_weight?: number | null
          pallet_ti?: number | null
          photos?: Json
          shelf_life_days?: number | null
          shipping_requirements?: string | null
          temperature_uom?: string | null
          upc?: string | null
          updated_at?: string
          updated_by?: string | null
          weight_uom?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_product_dimension_uom_fkey"
            columns: ["dimension_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "sales_product_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_product_grow_grade_id_fkey"
            columns: ["grow_grade_id"]
            isOneToOne: false
            referencedRelation: "grow_grade"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "sales_product_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_product_invnt_item_name_fkey"
            columns: ["invnt_item_name"]
            isOneToOne: false
            referencedRelation: "invnt_item_summary"
            referencedColumns: ["invnt_item_name"]
          },
          {
            foreignKeyName: "sales_product_item_uom_fkey"
            columns: ["item_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "sales_product_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_product_pack_uom_fkey"
            columns: ["pack_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "sales_product_temperature_uom_fkey"
            columns: ["temperature_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "sales_product_weight_uom_fkey"
            columns: ["weight_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      sales_product_price: {
        Row: {
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          farm_name: string
          id: string
          is_deleted: boolean
          org_id: string
          price_per_case: number
          sales_customer_group_name: string | null
          sales_customer_name: string | null
          sales_fob_name: string
          sales_product_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_to?: string | null
          farm_name: string
          id?: string
          is_deleted?: boolean
          org_id: string
          price_per_case: number
          sales_customer_group_name?: string | null
          sales_customer_name?: string | null
          sales_fob_name: string
          sales_product_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          farm_name?: string
          id?: string
          is_deleted?: boolean
          org_id?: string
          price_per_case?: number
          sales_customer_group_name?: string | null
          sales_customer_name?: string | null
          sales_fob_name?: string
          sales_product_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_product_price_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_product_price_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_product_price_sales_customer_group_name_fkey"
            columns: ["sales_customer_group_name"]
            isOneToOne: false
            referencedRelation: "sales_customer_group"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_product_price_sales_customer_name_fkey"
            columns: ["sales_customer_name"]
            isOneToOne: false
            referencedRelation: "sales_customer"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_product_price_sales_fob_name_fkey"
            columns: ["sales_fob_name"]
            isOneToOne: false
            referencedRelation: "sales_fob"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_product_price_sales_product_id_fkey"
            columns: ["sales_product_id"]
            isOneToOne: false
            referencedRelation: "sales_product"
            referencedColumns: ["code"]
          },
        ]
      }
      sys_access_level: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          is_deleted: boolean
          level: number
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          is_deleted?: boolean
          level: number
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          is_deleted?: boolean
          level?: number
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      sys_module: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          is_deleted: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          is_deleted?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          is_deleted?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      sys_sub_module: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          display_order: number
          is_deleted: boolean
          name: string
          sys_access_level_name: string
          sys_module_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          is_deleted?: boolean
          name: string
          sys_access_level_name: string
          sys_module_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          display_order?: number
          is_deleted?: boolean
          name?: string
          sys_access_level_name?: string
          sys_module_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sys_sub_module_sys_access_level_name_fkey"
            columns: ["sys_access_level_name"]
            isOneToOne: false
            referencedRelation: "sys_access_level"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sys_sub_module_sys_module_name_fkey"
            columns: ["sys_module_name"]
            isOneToOne: false
            referencedRelation: "hr_rba_navigation"
            referencedColumns: ["module_slug"]
          },
          {
            foreignKeyName: "sys_sub_module_sys_module_name_fkey"
            columns: ["sys_module_name"]
            isOneToOne: false
            referencedRelation: "sys_module"
            referencedColumns: ["name"]
          },
        ]
      }
      sys_uom: {
        Row: {
          category: string
          code: string
          created_at: string
          created_by: string | null
          is_deleted: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          category: string
          code: string
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          category?: string
          code?: string
          created_at?: string
          created_by?: string | null
          is_deleted?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      fin_expense_v: {
        Row: {
          account_name: string | null
          account_ref: string | null
          amount: number | null
          class_name: string | null
          created_at: string | null
          created_by: string | null
          description: string | null
          effective_amount: number | null
          farm_name: string | null
          id: string | null
          is_credit: boolean | null
          is_deleted: boolean | null
          macro_category: string | null
          month: number | null
          notes: string | null
          org_id: string | null
          payee_name: string | null
          txn_date: string | null
          updated_at: string | null
          updated_by: string | null
          year: number | null
        }
        Insert: {
          account_name?: string | null
          account_ref?: string | null
          amount?: number | null
          class_name?: string | null
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          effective_amount?: number | null
          farm_name?: string | null
          id?: string | null
          is_credit?: boolean | null
          is_deleted?: boolean | null
          macro_category?: string | null
          month?: never
          notes?: string | null
          org_id?: string | null
          payee_name?: string | null
          txn_date?: string | null
          updated_at?: string | null
          updated_by?: string | null
          year?: never
        }
        Update: {
          account_name?: string | null
          account_ref?: string | null
          amount?: number | null
          class_name?: string | null
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          effective_amount?: number | null
          farm_name?: string | null
          id?: string | null
          is_credit?: boolean | null
          is_deleted?: boolean | null
          macro_category?: string | null
          month?: never
          notes?: string | null
          org_id?: string | null
          payee_name?: string | null
          txn_date?: string | null
          updated_at?: string | null
          updated_by?: string | null
          year?: never
        }
        Relationships: [
          {
            foreignKeyName: "fin_expense_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fin_expense_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_cuke_harvest: {
        Row: {
          days_since_seed: number | null
          farm_name: string | null
          grade: string | null
          greenhouse: string | null
          greenhouse_net_weight: number | null
          gross_weight: number | null
          grow_cuke_seed_batch_id: string | null
          harvest_date: string | null
          id: string | null
          number_of_containers: number | null
          org_id: string | null
          seeding_date: string | null
          site_id: string | null
          variety: string | null
          weight_uom: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_harvest_weight_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_cuke_seed_batch_id_fkey"
            columns: ["grow_cuke_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_cuke_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_grade_id_fkey"
            columns: ["grade"]
            isOneToOne: false
            referencedRelation: "grow_grade"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "grow_harvest_weight_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "org_site"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_weight_uom_fkey"
            columns: ["weight_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
        ]
      }
      grow_lettuce_harvest: {
        Row: {
          boards_per_pond: number | null
          farm_name: string | null
          greenhouse_net_weight: number | null
          gross_weight: number | null
          grow_lettuce_seed_batch_id: string | null
          harvest_date: string | null
          id: string | null
          org_id: string | null
          pond: string | null
          pounds_per_board: number | null
          seed_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "grow_harvest_weight_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "grow_harvest_weight_grow_lettuce_seed_batch_id_fkey"
            columns: ["grow_lettuce_seed_batch_id"]
            isOneToOne: false
            referencedRelation: "grow_lettuce_seed_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grow_harvest_weight_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      grow_spray_restriction: {
        Row: {
          end_time: string | null
          farm_name: string | null
          ops_task_tracker_id: string | null
          org_id: string | null
          restriction_date: string | null
          restriction_stop: string | null
          restriction_type: string | null
          restriction_value: number | null
          site_id: string | null
          spray_stop: string | null
          start_time: string | null
        }
        Relationships: []
      }
      hr_payroll_by_task: {
        Row: {
          check_date: string | null
          compensation_manager_name: string | null
          discretionary_overtime_hours: number | null
          discretionary_overtime_pay: number | null
          hr_employee_name: string | null
          is_manager: boolean | null
          org_id: string | null
          regular_hours: number | null
          regular_pay: number | null
          scheduled_hours: number | null
          status: string | null
          task: string | null
          total_cost: number | null
          total_hours: number | null
          workers_compensation_code: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hr_employee_compensation_manager"
            columns: ["compensation_manager_name"]
            isOneToOne: false
            referencedRelation: "hr_employee"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_hr_employee_compensation_manager"
            columns: ["compensation_manager_name"]
            isOneToOne: false
            referencedRelation: "ops_task_weekly_schedule"
            referencedColumns: ["hr_employee_name"]
          },
        ]
      }
      hr_payroll_employee_comparison: {
        Row: {
          check_date: string | null
          compensation_manager_name: string | null
          discretionary_overtime_hours: number | null
          discretionary_overtime_pay: number | null
          discretionary_overtime_pay_delta: number | null
          hours_delta: number | null
          hr_employee_name: string | null
          org_id: string | null
          other_pay_delta: number | null
          regular_pay: number | null
          regular_pay_delta: number | null
          scheduled_hours: number | null
          status: string | null
          task: string | null
          total_cost: number | null
          total_cost_delta: number | null
          total_hours: number | null
          workers_compensation_code: string | null
        }
        Relationships: []
      }
      hr_rba_navigation: {
        Row: {
          can_delete: boolean | null
          can_edit: boolean | null
          can_verify: boolean | null
          module_display_name: string | null
          module_display_order: number | null
          module_id: string | null
          module_slug: string | null
          org_id: string | null
          sub_module_display_name: string | null
          sub_module_display_order: number | null
          sub_module_id: string | null
          sub_module_slug: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_module_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      invnt_item_summary: {
        Row: {
          burn_per_onhand: number | null
          burn_per_order: number | null
          burn_per_week: number | null
          burn_uom: string | null
          cushion_weeks: number | null
          days_since_onhand: number | null
          farm_name: string | null
          invnt_category_id: string | null
          invnt_item_name: string | null
          invnt_subcategory_id: string | null
          invnt_vendor_name: string | null
          is_auto_reorder: boolean | null
          is_frequently_used: boolean | null
          next_order_date: string | null
          onhand_date: string | null
          onhand_quantity: number | null
          onhand_quantity_in_burn: number | null
          onhand_uom: string | null
          order_uom: string | null
          ordered_quantity_in_burn: number | null
          org_id: string | null
          received_quantity_in_burn: number | null
          remaining_quantity_in_burn: number | null
          reorder_point_in_burn: number | null
          reorder_quantity_in_burn: number | null
          weeks_on_hand: number | null
        }
        Relationships: [
          {
            foreignKeyName: "invnt_item_burn_uom_fkey"
            columns: ["burn_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_item_invnt_category_id_fkey"
            columns: ["invnt_category_id"]
            isOneToOne: false
            referencedRelation: "invnt_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_item_invnt_subcategory_id_fkey"
            columns: ["invnt_subcategory_id"]
            isOneToOne: false
            referencedRelation: "invnt_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invnt_item_invnt_vendor_name_fkey"
            columns: ["invnt_vendor_name"]
            isOneToOne: false
            referencedRelation: "invnt_vendor"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "invnt_item_onhand_uom_fkey"
            columns: ["onhand_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_order_uom_fkey"
            columns: ["order_uom"]
            isOneToOne: false
            referencedRelation: "sys_uom"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "invnt_item_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      ops_task_weekly_schedule: {
        Row: {
          friday: string | null
          hr_department_name: string | null
          hr_employee_name: string | null
          hr_work_authorization_name: string | null
          is_over_ot_threshold: boolean | null
          monday: string | null
          org_id: string | null
          ot_threshold_weekly: number | null
          saturday: string | null
          sunday: string | null
          task: string | null
          thursday: string | null
          total_hours: number | null
          tuesday: string | null
          wednesday: string | null
          week_start_date: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_employee_hr_department_name_fkey"
            columns: ["hr_department_name"]
            isOneToOne: false
            referencedRelation: "hr_department"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "hr_employee_hr_work_authorization_name_fkey"
            columns: ["hr_work_authorization_name"]
            isOneToOne: false
            referencedRelation: "hr_work_authorization"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "ops_task_schedule_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_invoice_v: {
        Row: {
          cases: number | null
          created_at: string | null
          created_by: string | null
          customer_group: string | null
          customer_name: string | null
          dollars: number | null
          dow: number | null
          farm_name: string | null
          grade: string | null
          id: string | null
          invoice_date: string | null
          invoice_number: string | null
          is_deleted: boolean | null
          iso_week: number | null
          iso_year: number | null
          month: number | null
          notes: string | null
          org_id: string | null
          pounds: number | null
          product_code: string | null
          updated_at: string | null
          updated_by: string | null
          variety: string | null
          year: number | null
        }
        Insert: {
          cases?: number | null
          created_at?: string | null
          created_by?: string | null
          customer_group?: string | null
          customer_name?: string | null
          dollars?: number | null
          dow?: never
          farm_name?: string | null
          grade?: string | null
          id?: string | null
          invoice_date?: string | null
          invoice_number?: string | null
          is_deleted?: boolean | null
          iso_week?: never
          iso_year?: never
          month?: never
          notes?: string | null
          org_id?: string | null
          pounds?: number | null
          product_code?: string | null
          updated_at?: string | null
          updated_by?: string | null
          variety?: string | null
          year?: never
        }
        Update: {
          cases?: number | null
          created_at?: string | null
          created_by?: string | null
          customer_group?: string | null
          customer_name?: string | null
          dollars?: number | null
          dow?: never
          farm_name?: string | null
          grade?: string | null
          id?: string | null
          invoice_date?: string | null
          invoice_number?: string | null
          is_deleted?: boolean | null
          iso_week?: never
          iso_year?: never
          month?: never
          notes?: string | null
          org_id?: string | null
          pounds?: number | null
          product_code?: string | null
          updated_at?: string | null
          updated_by?: string | null
          variety?: string | null
          year?: never
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoice_farm_name_fkey"
            columns: ["farm_name"]
            isOneToOne: false
            referencedRelation: "org_farm"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "sales_invoice_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "org"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      chat_query: { Args: { q: string }; Returns: Json }
      chat_schema: { Args: never; Returns: Json }
      get_user_org_ids: { Args: never; Returns: string[] }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  storage: {
    Tables: {
      buckets: {
        Row: {
          allowed_mime_types: string[] | null
          avif_autodetection: boolean | null
          created_at: string | null
          file_size_limit: number | null
          id: string
          name: string
          owner: string | null
          owner_id: string | null
          public: boolean | null
          type: Database["storage"]["Enums"]["buckettype"]
          updated_at: string | null
        }
        Insert: {
          allowed_mime_types?: string[] | null
          avif_autodetection?: boolean | null
          created_at?: string | null
          file_size_limit?: number | null
          id: string
          name: string
          owner?: string | null
          owner_id?: string | null
          public?: boolean | null
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string | null
        }
        Update: {
          allowed_mime_types?: string[] | null
          avif_autodetection?: boolean | null
          created_at?: string | null
          file_size_limit?: number | null
          id?: string
          name?: string
          owner?: string | null
          owner_id?: string | null
          public?: boolean | null
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string | null
        }
        Relationships: []
      }
      buckets_analytics: {
        Row: {
          created_at: string
          deleted_at: string | null
          format: string
          id: string
          name: string
          type: Database["storage"]["Enums"]["buckettype"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          format?: string
          id?: string
          name: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          format?: string
          id?: string
          name?: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Relationships: []
      }
      buckets_vectors: {
        Row: {
          created_at: string
          id: string
          type: Database["storage"]["Enums"]["buckettype"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Relationships: []
      }
      migrations: {
        Row: {
          executed_at: string | null
          hash: string
          id: number
          name: string
        }
        Insert: {
          executed_at?: string | null
          hash: string
          id: number
          name: string
        }
        Update: {
          executed_at?: string | null
          hash?: string
          id?: number
          name?: string
        }
        Relationships: []
      }
      objects: {
        Row: {
          bucket_id: string | null
          created_at: string | null
          id: string
          last_accessed_at: string | null
          metadata: Json | null
          name: string | null
          owner: string | null
          owner_id: string | null
          path_tokens: string[] | null
          updated_at: string | null
          user_metadata: Json | null
          version: string | null
        }
        Insert: {
          bucket_id?: string | null
          created_at?: string | null
          id?: string
          last_accessed_at?: string | null
          metadata?: Json | null
          name?: string | null
          owner?: string | null
          owner_id?: string | null
          path_tokens?: string[] | null
          updated_at?: string | null
          user_metadata?: Json | null
          version?: string | null
        }
        Update: {
          bucket_id?: string | null
          created_at?: string | null
          id?: string
          last_accessed_at?: string | null
          metadata?: Json | null
          name?: string | null
          owner?: string | null
          owner_id?: string | null
          path_tokens?: string[] | null
          updated_at?: string | null
          user_metadata?: Json | null
          version?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "objects_bucketId_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets"
            referencedColumns: ["id"]
          },
        ]
      }
      s3_multipart_uploads: {
        Row: {
          bucket_id: string
          created_at: string
          id: string
          in_progress_size: number
          key: string
          metadata: Json | null
          owner_id: string | null
          upload_signature: string
          user_metadata: Json | null
          version: string
        }
        Insert: {
          bucket_id: string
          created_at?: string
          id: string
          in_progress_size?: number
          key: string
          metadata?: Json | null
          owner_id?: string | null
          upload_signature: string
          user_metadata?: Json | null
          version: string
        }
        Update: {
          bucket_id?: string
          created_at?: string
          id?: string
          in_progress_size?: number
          key?: string
          metadata?: Json | null
          owner_id?: string | null
          upload_signature?: string
          user_metadata?: Json | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "s3_multipart_uploads_bucket_id_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets"
            referencedColumns: ["id"]
          },
        ]
      }
      s3_multipart_uploads_parts: {
        Row: {
          bucket_id: string
          created_at: string
          etag: string
          id: string
          key: string
          owner_id: string | null
          part_number: number
          size: number
          upload_id: string
          version: string
        }
        Insert: {
          bucket_id: string
          created_at?: string
          etag: string
          id?: string
          key: string
          owner_id?: string | null
          part_number: number
          size?: number
          upload_id: string
          version: string
        }
        Update: {
          bucket_id?: string
          created_at?: string
          etag?: string
          id?: string
          key?: string
          owner_id?: string | null
          part_number?: number
          size?: number
          upload_id?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "s3_multipart_uploads_parts_bucket_id_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "s3_multipart_uploads_parts_upload_id_fkey"
            columns: ["upload_id"]
            isOneToOne: false
            referencedRelation: "s3_multipart_uploads"
            referencedColumns: ["id"]
          },
        ]
      }
      vector_indexes: {
        Row: {
          bucket_id: string
          created_at: string
          data_type: string
          dimension: number
          distance_metric: string
          id: string
          metadata_configuration: Json | null
          name: string
          updated_at: string
        }
        Insert: {
          bucket_id: string
          created_at?: string
          data_type: string
          dimension: number
          distance_metric: string
          id?: string
          metadata_configuration?: Json | null
          name: string
          updated_at?: string
        }
        Update: {
          bucket_id?: string
          created_at?: string
          data_type?: string
          dimension?: number
          distance_metric?: string
          id?: string
          metadata_configuration?: Json | null
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "vector_indexes_bucket_id_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets_vectors"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      allow_any_operation: {
        Args: { expected_operations: string[] }
        Returns: boolean
      }
      allow_only_operation: {
        Args: { expected_operation: string }
        Returns: boolean
      }
      can_insert_object: {
        Args: { bucketid: string; metadata: Json; name: string; owner: string }
        Returns: undefined
      }
      extension: { Args: { name: string }; Returns: string }
      filename: { Args: { name: string }; Returns: string }
      foldername: { Args: { name: string }; Returns: string[] }
      get_common_prefix: {
        Args: { p_delimiter: string; p_key: string; p_prefix: string }
        Returns: string
      }
      get_size_by_bucket: {
        Args: never
        Returns: {
          bucket_id: string
          size: number
        }[]
      }
      list_multipart_uploads_with_delimiter: {
        Args: {
          bucket_id: string
          delimiter_param: string
          max_keys?: number
          next_key_token?: string
          next_upload_token?: string
          prefix_param: string
        }
        Returns: {
          created_at: string
          id: string
          key: string
        }[]
      }
      list_objects_with_delimiter: {
        Args: {
          _bucket_id: string
          delimiter_param: string
          max_keys?: number
          next_token?: string
          prefix_param: string
          sort_order?: string
          start_after?: string
        }
        Returns: {
          created_at: string
          id: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
      operation: { Args: never; Returns: string }
      search: {
        Args: {
          bucketname: string
          levels?: number
          limits?: number
          offsets?: number
          prefix: string
          search?: string
          sortcolumn?: string
          sortorder?: string
        }
        Returns: {
          created_at: string
          id: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
      search_by_timestamp: {
        Args: {
          p_bucket_id: string
          p_level: number
          p_limit: number
          p_prefix: string
          p_sort_column: string
          p_sort_column_after: string
          p_sort_order: string
          p_start_after: string
        }
        Returns: {
          created_at: string
          id: string
          key: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
      search_v2: {
        Args: {
          bucket_name: string
          levels?: number
          limits?: number
          prefix: string
          sort_column?: string
          sort_column_after?: string
          sort_order?: string
          start_after?: string
        }
        Returns: {
          created_at: string
          id: string
          key: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
    }
    Enums: {
      buckettype: "STANDARD" | "ANALYTICS" | "VECTOR"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
  storage: {
    Enums: {
      buckettype: ["STANDARD", "ANALYTICS", "VECTOR"],
    },
  },
} as const
