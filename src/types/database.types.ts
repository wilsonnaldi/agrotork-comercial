export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      app_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "app_settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_db_role: string
          actor_email: string | null
          actor_kind: string
          actor_name: string | null
          actor_role: Database["public"]["Enums"]["user_role"] | null
          actor_user_id: string | null
          changed_fields: string[] | null
          entity_id: string
          entity_label: string | null
          entity_type: string
          id: number
          metadata: Json
          new_data: Json | null
          occurred_at: string
          old_data: Json | null
          operation: string
          parent_id: string | null
          parent_type: string | null
        }
        Insert: {
          action: string
          actor_db_role: string
          actor_email?: string | null
          actor_kind?: string
          actor_name?: string | null
          actor_role?: Database["public"]["Enums"]["user_role"] | null
          actor_user_id?: string | null
          changed_fields?: string[] | null
          entity_id: string
          entity_label?: string | null
          entity_type: string
          id?: number
          metadata?: Json
          new_data?: Json | null
          occurred_at?: string
          old_data?: Json | null
          operation: string
          parent_id?: string | null
          parent_type?: string | null
        }
        Update: {
          action?: string
          actor_db_role?: string
          actor_email?: string | null
          actor_kind?: string
          actor_name?: string | null
          actor_role?: Database["public"]["Enums"]["user_role"] | null
          actor_user_id?: string | null
          changed_fields?: string[] | null
          entity_id?: string
          entity_label?: string | null
          entity_type?: string
          id?: number
          metadata?: Json
          new_data?: Json | null
          occurred_at?: string
          old_data?: Json | null
          operation?: string
          parent_id?: string | null
          parent_type?: string | null
        }
        Relationships: []
      }
      brands: {
        Row: {
          created_at: string
          deleted_at: string | null
          description: string | null
          id: string
          is_active: boolean
          logo_url: string | null
          name: string
          slug: string
          sort_order: number
          updated_at: string
          website: string | null
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          logo_url?: string | null
          name: string
          slug: string
          sort_order?: number
          updated_at?: string
          website?: string | null
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          logo_url?: string | null
          name?: string
          slug?: string
          sort_order?: number
          updated_at?: string
          website?: string | null
        }
        Relationships: []
      }
      categories: {
        Row: {
          created_at: string
          deleted_at: string | null
          description: string | null
          id: string
          is_active: boolean
          name: string
          parent_id: string | null
          slug: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          parent_id?: string | null
          slug: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          parent_id?: string | null
          slug?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "categories_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
        ]
      }
      customers: {
        Row: {
          address: string | null
          address_complement: string | null
          address_number: string | null
          city: string | null
          created_at: string
          created_by: string | null
          deleted_at: string | null
          district: string | null
          document: string | null
          email: string | null
          id: string
          is_active: boolean
          name: string
          notes: string | null
          person_type: Database["public"]["Enums"]["person_type"]
          phone: string | null
          state: string | null
          state_registration: string | null
          trade_name: string | null
          updated_at: string
          updated_by: string | null
          whatsapp: string | null
          zip_code: string | null
        }
        Insert: {
          address?: string | null
          address_complement?: string | null
          address_number?: string | null
          city?: string | null
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          district?: string | null
          document?: string | null
          email?: string | null
          id?: string
          is_active?: boolean
          name: string
          notes?: string | null
          person_type?: Database["public"]["Enums"]["person_type"]
          phone?: string | null
          state?: string | null
          state_registration?: string | null
          trade_name?: string | null
          updated_at?: string
          updated_by?: string | null
          whatsapp?: string | null
          zip_code?: string | null
        }
        Update: {
          address?: string | null
          address_complement?: string | null
          address_number?: string | null
          city?: string | null
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          district?: string | null
          document?: string | null
          email?: string | null
          id?: string
          is_active?: boolean
          name?: string
          notes?: string | null
          person_type?: Database["public"]["Enums"]["person_type"]
          phone?: string | null
          state?: string | null
          state_registration?: string | null
          trade_name?: string | null
          updated_at?: string
          updated_by?: string | null
          whatsapp?: string | null
          zip_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      kit_items: {
        Row: {
          created_at: string
          id: string
          item_type: Database["public"]["Enums"]["kit_item_type"]
          kit_id: string
          notes: string | null
          product_id: string
          quantity: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          item_type?: Database["public"]["Enums"]["kit_item_type"]
          kit_id: string
          notes?: string | null
          product_id: string
          quantity?: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          item_type?: Database["public"]["Enums"]["kit_item_type"]
          kit_id?: string
          notes?: string | null
          product_id?: string
          quantity?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "kit_items_kit_id_fkey"
            columns: ["kit_id"]
            isOneToOne: false
            referencedRelation: "kits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "kit_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      kits: {
        Row: {
          category_id: string | null
          code: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          description: string | null
          discount_percent: number
          id: string
          image_url: string | null
          is_active: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          category_id?: string | null
          code: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          discount_percent?: number
          id?: string
          image_url?: string | null
          is_active?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          category_id?: string | null
          code?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          discount_percent?: number
          id?: string
          image_url?: string | null
          is_active?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "kits_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "kits_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "kits_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      margin_rules: {
        Row: {
          category_id: string | null
          cost_basis: string
          created_at: string
          id: string
          is_active: boolean
          mode: string
          notes: string | null
          percent: number
          rounding: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          category_id?: string | null
          cost_basis?: string
          created_at?: string
          id?: string
          is_active?: boolean
          mode?: string
          notes?: string | null
          percent: number
          rounding?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          category_id?: string | null
          cost_basis?: string
          created_at?: string
          id?: string
          is_active?: boolean
          mode?: string
          notes?: string | null
          percent?: number
          rounding?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "margin_rules_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: true
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "margin_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      price_conditions: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          is_default: boolean
          name: string
          payment_days: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          name: string
          payment_days?: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          name?: string
          payment_days?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      product_costs: {
        Row: {
          condition_id: string
          cost_price: number
          created_at: string
          id: string
          product_id: string
          source_catalog: string | null
          source_reference: string | null
          source_version: string | null
          updated_at: string
          updated_by: string | null
          valid_from: string
          valid_to: string | null
        }
        Insert: {
          condition_id: string
          cost_price?: number
          created_at?: string
          id?: string
          product_id: string
          source_catalog?: string | null
          source_reference?: string | null
          source_version?: string | null
          updated_at?: string
          updated_by?: string | null
          valid_from?: string
          valid_to?: string | null
        }
        Update: {
          condition_id?: string
          cost_price?: number
          created_at?: string
          id?: string
          product_id?: string
          source_catalog?: string | null
          source_reference?: string | null
          source_version?: string | null
          updated_at?: string
          updated_by?: string | null
          valid_from?: string
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_costs_condition_id_fkey"
            columns: ["condition_id"]
            isOneToOne: false
            referencedRelation: "price_conditions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_costs_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_costs_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          brand_id: string | null
          category_id: string | null
          code: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          description: string | null
          id: string
          image_url: string | null
          is_active: boolean
          manufacturer_code: string | null
          name: string
          notes: string | null
          sale_price: number
          sale_price_set_at: string | null
          source_brand: string | null
          source_catalog: string | null
          source_imported_at: string | null
          source_reference: string | null
          source_type: Database["public"]["Enums"]["product_source_type"]
          source_version: string | null
          technical_data: Json
          unit_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          brand_id?: string | null
          category_id?: string | null
          code: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean
          manufacturer_code?: string | null
          name: string
          notes?: string | null
          sale_price?: number
          sale_price_set_at?: string | null
          source_brand?: string | null
          source_catalog?: string | null
          source_imported_at?: string | null
          source_reference?: string | null
          source_type?: Database["public"]["Enums"]["product_source_type"]
          source_version?: string | null
          technical_data?: Json
          unit_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          brand_id?: string | null
          category_id?: string | null
          code?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean
          manufacturer_code?: string | null
          name?: string
          notes?: string | null
          sale_price?: number
          sale_price_set_at?: string | null
          source_brand?: string | null
          source_catalog?: string | null
          source_imported_at?: string | null
          source_reference?: string | null
          source_type?: Database["public"]["Enums"]["product_source_type"]
          source_version?: string | null
          technical_data?: Json
          unit_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "products_brand_id_fkey"
            columns: ["brand_id"]
            isOneToOne: false
            referencedRelation: "brands"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_unit_id_fkey"
            columns: ["unit_id"]
            isOneToOne: false
            referencedRelation: "units"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          full_name: string
          id: string
          is_active: boolean
          phone: string | null
          role: Database["public"]["Enums"]["user_role"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name?: string
          id: string
          is_active?: boolean
          phone?: string | null
          role?: Database["public"]["Enums"]["user_role"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          is_active?: boolean
          phone?: string | null
          role?: Database["public"]["Enums"]["user_role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_items: {
        Row: {
          brand_snapshot: string | null
          code_snapshot: string | null
          components_snapshot: Json | null
          created_at: string
          description_snapshot: string | null
          discount_percent: number
          id: string
          image_url_snapshot: string | null
          kind: Database["public"]["Enums"]["item_kind"]
          kit_id: string | null
          line_total: number | null
          name_snapshot: string
          notes: string | null
          product_id: string | null
          quantity: number
          quote_id: string
          sort_order: number
          unit_cost_snapshot: number | null
          unit_price: number
          unit_snapshot: string | null
          updated_at: string
        }
        Insert: {
          brand_snapshot?: string | null
          code_snapshot?: string | null
          components_snapshot?: Json | null
          created_at?: string
          description_snapshot?: string | null
          discount_percent?: number
          id?: string
          image_url_snapshot?: string | null
          kind?: Database["public"]["Enums"]["item_kind"]
          kit_id?: string | null
          line_total?: number | null
          name_snapshot: string
          notes?: string | null
          product_id?: string | null
          quantity?: number
          quote_id: string
          sort_order?: number
          unit_cost_snapshot?: number | null
          unit_price?: number
          unit_snapshot?: string | null
          updated_at?: string
        }
        Update: {
          brand_snapshot?: string | null
          code_snapshot?: string | null
          components_snapshot?: Json | null
          created_at?: string
          description_snapshot?: string | null
          discount_percent?: number
          id?: string
          image_url_snapshot?: string | null
          kind?: Database["public"]["Enums"]["item_kind"]
          kit_id?: string | null
          line_total?: number | null
          name_snapshot?: string
          notes?: string | null
          product_id?: string | null
          quantity?: number
          quote_id?: string
          sort_order?: number
          unit_cost_snapshot?: number | null
          unit_price?: number
          unit_snapshot?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_items_kit_id_fkey"
            columns: ["kit_id"]
            isOneToOne: false
            referencedRelation: "kits"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_items_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_sequences: {
        Row: {
          last_number: number
          year: number
        }
        Insert: {
          last_number?: number
          year: number
        }
        Update: {
          last_number?: number
          year?: number
        }
        Relationships: []
      }
      quote_share_tokens: {
        Row: {
          created_at: string
          created_by: string | null
          expires_at: string | null
          id: string
          quote_id: string
          revoked_at: string | null
          token: string
          view_count: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          expires_at?: string | null
          id?: string
          quote_id: string
          revoked_at?: string | null
          token?: string
          view_count?: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          expires_at?: string | null
          id?: string
          quote_id?: string
          revoked_at?: string | null
          token?: string
          view_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_share_tokens_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_share_tokens_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
        ]
      }
      quotes: {
        Row: {
          approved_at: string | null
          created_at: string
          created_by: string | null
          customer_id: string
          deleted_at: string | null
          delivery_terms: string | null
          discount_amount: number
          discount_percent: number
          id: string
          internal_notes: string | null
          issue_date: string
          notes: string | null
          number: string
          owner_id: string
          payment_terms: string | null
          rejected_at: string | null
          sent_at: string | null
          sequence_number: number
          sequence_year: number
          shipping_amount: number
          status: Database["public"]["Enums"]["quote_status"]
          subtotal: number
          total: number
          updated_at: string
          updated_by: string | null
          valid_until: string | null
        }
        Insert: {
          approved_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_id: string
          deleted_at?: string | null
          delivery_terms?: string | null
          discount_amount?: number
          discount_percent?: number
          id?: string
          internal_notes?: string | null
          issue_date?: string
          notes?: string | null
          number: string
          owner_id: string
          payment_terms?: string | null
          rejected_at?: string | null
          sent_at?: string | null
          sequence_number: number
          sequence_year: number
          shipping_amount?: number
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal?: number
          total?: number
          updated_at?: string
          updated_by?: string | null
          valid_until?: string | null
        }
        Update: {
          approved_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string
          deleted_at?: string | null
          delivery_terms?: string | null
          discount_amount?: number
          discount_percent?: number
          id?: string
          internal_notes?: string | null
          issue_date?: string
          notes?: string | null
          number?: string
          owner_id?: string
          payment_terms?: string | null
          rejected_at?: string | null
          sent_at?: string | null
          sequence_number?: number
          sequence_year?: number
          shipping_amount?: number
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal?: number
          total?: number
          updated_at?: string
          updated_by?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quotes_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      units: {
        Row: {
          allows_fraction: boolean
          code: string
          created_at: string
          id: string
          is_active: boolean
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          allows_fraction?: boolean
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          allows_fraction?: boolean
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      kits_with_price: {
        Row: {
          category_id: string | null
          code: string | null
          components_total: number | null
          created_at: string | null
          description: string | null
          discount_percent: number | null
          id: string | null
          image_url: string | null
          is_active: boolean | null
          items_count: number | null
          name: string | null
          optional_count: number | null
          optional_total: number | null
          required_count: number | null
          suggested_price: number | null
          updated_at: string | null
        }
        Relationships: []
      }
      products_list: {
        Row: {
          brand_id: string | null
          brand_name: string | null
          category_id: string | null
          category_name: string | null
          code: string | null
          cost_price: number | null
          created_at: string | null
          description: string | null
          id: string | null
          image_url: string | null
          is_active: boolean | null
          manufacturer_code: string | null
          margin_percent: number | null
          name: string | null
          notes: string | null
          sale_price: number | null
          sale_price_set_at: string | null
          source_brand: string | null
          source_catalog: string | null
          source_imported_at: string | null
          source_reference: string | null
          source_type: Database["public"]["Enums"]["product_source_type"] | null
          source_version: string | null
          technical_data: Json | null
          unit_code: string | null
          unit_id: string | null
          unit_name: string | null
          updated_at: string | null
        }
        Relationships: []
      }
      quotes_list: {
        Row: {
          created_at: string | null
          customer_city: string | null
          customer_id: string | null
          customer_name: string | null
          id: string | null
          issue_date: string | null
          items_count: number | null
          number: string | null
          owner_id: string | null
          owner_name: string | null
          status: Database["public"]["Enums"]["quote_status"] | null
          subtotal: number | null
          total: number | null
          updated_at: string | null
          valid_until: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      apply_margin_rules: {
        Args: {
          p_category_id?: string
          p_todas?: boolean
          p_dry_run?: boolean
        }
        Returns: {
          product_id: string
          code: string
          name: string
          categoria: string
          preco_atual: number
          preco_sugerido: number
          aplicado: boolean
        }[]
      }
      auth_role: {
        Args: Record<PropertyKey, never>
        Returns: Database["public"]["Enums"]["user_role"]
      }
      discard_quote_draft: {
        Args: {
          p_quote_id: string
        }
        Returns: boolean
      }
      expire_quotes: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      get_shared_quote: {
        Args: {
          p_token: string
        }
        Returns: Json
      }
      is_active_user: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      is_admin: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      next_quote_number: {
        Args: {
          p_year?: number
        }
        Returns: {
          seq_year: number
          seq_number: number
          formatted: string
        }[]
      }
      only_digits: {
        Args: {
          value: string
        }
        Returns: string
      }
      owns_quote: {
        Args: {
          p_quote_id: string
        }
        Returns: boolean
      }
      purge_test_products: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      quote_is_editable: {
        Args: {
          p_quote_id: string
        }
        Returns: boolean
      }
      quote_is_shareable: {
        Args: {
          p_status: Database["public"]["Enums"]["quote_status"]
        }
        Returns: boolean
      }
      recalculate_quote_totals: {
        Args: {
          p_quote_id: string
        }
        Returns: undefined
      }
      round_commercial: {
        Args: {
          p_value: number
          p_mode: string
        }
        Returns: number
      }
      set_product_cost: {
        Args: {
          p_product_id: string
          p_cost_price: number
          p_condition_code?: string
          p_updated_by?: string
        }
        Returns: undefined
      }
      slugify: {
        Args: {
          value: string
        }
        Returns: string
      }
      suggested_sale_price: {
        Args: {
          p_product_id: string
        }
        Returns: number
      }
    }
    Enums: {
      item_kind: "product" | "kit" | "custom"
      kit_item_type: "required" | "optional"
      person_type: "individual" | "company"
      product_source_type: "manual" | "manufacturer_catalog" | "price_list" | "test_data"
      quote_status: "draft" | "sent" | "approved" | "rejected" | "expired" | "cancelled"
      user_role: "admin" | "salesperson"
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
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends { Insert: infer I }
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
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends { Update: infer U }
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
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      item_kind: ["product", "kit", "custom"],
      kit_item_type: ["required", "optional"],
      person_type: ["individual", "company"],
      product_source_type: ["manual", "manufacturer_catalog", "price_list", "test_data"],
      quote_status: ["draft", "sent", "approved", "rejected", "expired", "cancelled"],
      user_role: ["admin", "salesperson"],
    },
  },
} as const
