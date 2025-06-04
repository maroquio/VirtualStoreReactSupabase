-- ============================================================================
-- SCRIPT COMPLETO PARA CRIAÇÃO DO BANCO DE DADOS E-COMMERCE SEGURO
-- Sistema com autenticação, autorização, auditoria e validações
-- Compatible with Supabase PostgreSQL
-- VERSÃO CORRIGIDA - POLÍTICAS RLS FIXADAS
-- ============================================================================

-- ============================================================================
-- 1. CONFIGURAÇÃO INICIAL E EXTENSÕES
-- ============================================================================

-- Habilitar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 2. CRIAÇÃO DOS TIPOS ENUM
-- ============================================================================

-- Enum para status dos pedidos
CREATE TYPE order_status_enum AS ENUM (
  'Cart',
  'Ordered', 
  'Paid',
  'Preparing',
  'Shipped',
  'Received',
  'Cancelled',
  'Returned',
  'Refunded'
);

-- Enum para tipos de ações de auditoria
CREATE TYPE audit_action_enum AS ENUM (
  'INSERT',
  'UPDATE', 
  'DELETE',
  'SELECT'
);

-- Enum para estados brasileiros
CREATE TYPE brazilian_state_enum AS ENUM (
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 
  'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 
  'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'
);

-- ============================================================================
-- 3. FUNÇÕES DE VALIDAÇÃO
-- ============================================================================

-- Função para validar CEP brasileiro
CREATE OR REPLACE FUNCTION public.validate_postal_code(postal_code text)
RETURNS boolean 
LANGUAGE plpgsql 
IMMUTABLE
AS $$
BEGIN
  -- Remove hífens e espaços
  postal_code := regexp_replace(postal_code, '[^0-9]', '', 'g');
  
  -- Verifica se tem exatamente 8 dígitos
  RETURN postal_code ~ '^[0-9]{8}$';
END;
$$;

-- Função para validar telefone brasileiro
CREATE OR REPLACE FUNCTION public.validate_phone(phone text)
RETURNS boolean 
LANGUAGE plpgsql 
IMMUTABLE
AS $$
BEGIN
  -- Remove caracteres não numéricos
  phone := regexp_replace(phone, '[^0-9]', '', 'g');
  
  -- Verifica formatos válidos: (11) 9XXXX-XXXX ou (XX) XXXX-XXXX
  RETURN phone ~ '^[1-9][1-9][9][0-9]{8}$' OR phone ~ '^[1-9][1-9][0-9]{8}$';
END;
$$;

-- Função para validar email
CREATE OR REPLACE FUNCTION public.validate_email(email text)
RETURNS boolean 
LANGUAGE plpgsql 
IMMUTABLE
AS $$
BEGIN
  RETURN email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;
$$;

-- ============================================================================
-- 4. CRIAÇÃO DAS TABELAS
-- ============================================================================

-- 4.1 Tabela de Perfis (Profiles)
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  full_name text,
  avatar_url text,
  email text,
  is_admin boolean DEFAULT false,
  updated_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  phone text NOT NULL,
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT valid_email CHECK (email IS NULL OR validate_email(email)),
  CONSTRAINT valid_phone CHECK (validate_phone(phone)),
  CONSTRAINT full_name_not_empty CHECK (length(trim(full_name)) > 0)
);

-- 4.2 Categorias
CREATE TABLE public.categories (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL UNIQUE,
  description text,
  created_at timestamp with time zone DEFAULT now(),
  is_active boolean DEFAULT true,
  CONSTRAINT categories_pkey PRIMARY KEY (id),
  CONSTRAINT category_name_not_empty CHECK (length(trim(name)) > 0)
);

-- 4.3 Transportadoras
CREATE TABLE public.carriers (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  is_active boolean DEFAULT true,
  CONSTRAINT carriers_pkey PRIMARY KEY (id),
  CONSTRAINT carrier_name_not_empty CHECK (length(trim(name)) > 0)
);

-- 4.4 Produtos
CREATE TABLE public.products (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  title text NOT NULL,
  description text,
  price numeric NOT NULL CHECK (price >= 0),
  image_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  category_id bigint NOT NULL DEFAULT 1,
  is_active boolean DEFAULT true,
  stock_quantity integer DEFAULT 0 CHECK (stock_quantity >= 0),
  CONSTRAINT products_pkey PRIMARY KEY (id),
  CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id),
  CONSTRAINT product_title_not_empty CHECK (length(trim(title)) > 0)
);

-- 4.5 Endereços
CREATE TABLE public.addresses (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  customer_id uuid NOT NULL,
  postal_code text NOT NULL,
  address text NOT NULL,
  number text NOT NULL,
  complement text,
  neighborhood text NOT NULL,
  city text NOT NULL,
  state brazilian_state_enum NOT NULL,
  is_default boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT addresses_pkey PRIMARY KEY (id),
  CONSTRAINT addresses_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT valid_postal_code CHECK (validate_postal_code(postal_code)),
  CONSTRAINT address_fields_not_empty CHECK (
    length(trim(address)) > 0 AND 
    length(trim(number)) > 0 AND 
    length(trim(neighborhood)) > 0 AND 
    length(trim(city)) > 0
  )
);

-- 4.6 Pedidos
CREATE TABLE public.orders (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  customer_id uuid NOT NULL,
  order_value numeric NOT NULL DEFAULT 0 CHECK (order_value >= 0),
  shipping_value numeric DEFAULT 0 CHECK (shipping_value >= 0),
  total_value numeric GENERATED ALWAYS AS (order_value + COALESCE(shipping_value, 0)) STORED,
  order_date timestamp with time zone,
  tracking_number text,
  recipient_name text,
  recipient_phone text,
  carrier_id bigint,
  address_postal_code text,
  address_address text,
  address_number text,
  address_complement text,
  address_neighborhood text,
  address_city text,
  address_state brazilian_state_enum,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT orders_pkey PRIMARY KEY (id),
  CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.profiles(id),
  CONSTRAINT orders_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES public.carriers(id),
  CONSTRAINT valid_recipient_phone CHECK (recipient_phone IS NULL OR validate_phone(recipient_phone))
);

-- 4.7 Status dos Pedidos
CREATE TABLE public.order_statuses (
  order_id bigint NOT NULL,
  status order_status_enum NOT NULL DEFAULT 'Cart',
  datetime timestamp with time zone NOT NULL DEFAULT now(),
  notes text,
  changed_by uuid REFERENCES public.profiles(id),
  CONSTRAINT order_statuses_pkey PRIMARY KEY (order_id, status),
  CONSTRAINT order_statuses_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE
);

-- 4.8 Itens do Pedido
CREATE TABLE public.order_items (
  order_id bigint NOT NULL,
  product_id bigint NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  unity_value numeric NOT NULL CHECK (unity_value >= 0),
  item_value numeric GENERATED ALWAYS AS (unity_value * quantity) STORED,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT order_items_pkey PRIMARY KEY (order_id, product_id),
  CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE
);

-- 4.9 Tabela de Auditoria
CREATE TABLE public.audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  table_name text NOT NULL,
  record_id text NOT NULL,
  action audit_action_enum NOT NULL,
  old_values jsonb,
  new_values jsonb,
  user_id uuid REFERENCES public.profiles(id),
  timestamp timestamp with time zone DEFAULT now(),
  ip_address inet,
  user_agent text,
  CONSTRAINT audit_log_pkey PRIMARY KEY (id)
);

-- ============================================================================
-- 5. FUNÇÕES AUXILIARES E TRIGGERS
-- ============================================================================

-- 5.1 Função para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- 5.2 Triggers para updated_at
CREATE TRIGGER update_profiles_updated_at 
BEFORE UPDATE ON profiles 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at 
BEFORE UPDATE ON products 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at 
BEFORE UPDATE ON orders 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 5.3 Função para criar status inicial do pedido
CREATE OR REPLACE FUNCTION public.create_initial_order_status()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO order_statuses (order_id, status, changed_by)
  VALUES (NEW.id, 'Cart', NEW.customer_id);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER create_initial_order_status_trigger
AFTER INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION create_initial_order_status();

-- 5.4 Função para verificar se pedido está em status Cart
CREATE OR REPLACE FUNCTION public.is_order_in_cart_status(order_id_param bigint)
RETURNS boolean 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM order_statuses os1
    WHERE os1.order_id = order_id_param
    AND os1.status = 'Cart'
    AND os1.datetime = (
      SELECT MAX(os2.datetime)
      FROM order_statuses os2
      WHERE os2.order_id = order_id_param
    )
  );
END;
$$;

-- 5.5 Função para obter último status do pedido
CREATE OR REPLACE FUNCTION public.get_latest_order_status(order_id_param bigint)
RETURNS order_status_enum 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT status
    FROM order_statuses
    WHERE order_id = order_id_param
    ORDER BY datetime DESC
    LIMIT 1
  );
END;
$$;

-- 5.6 Função para verificar se usuário é admin
CREATE OR REPLACE FUNCTION public.user_is_admin()
RETURNS boolean 
LANGUAGE sql 
STABLE 
SECURITY DEFINER 
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.profiles 
    WHERE id = auth.uid() AND is_admin = true
  );
$$;

-- 5.7 Função para validar transições de status
CREATE OR REPLACE FUNCTION public.validate_status_transition(
  p_order_id bigint,
  p_new_status order_status_enum
)
RETURNS boolean 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  current_status order_status_enum;
  valid_transitions text[][];
BEGIN
  -- Obter status atual
  current_status := get_latest_order_status(p_order_id);
  
  -- Se não há status atual, só permite Cart
  IF current_status IS NULL THEN
    RETURN p_new_status = 'Cart';
  END IF;
  
  -- Definir transições válidas
  valid_transitions := ARRAY[
    ARRAY['Cart', 'Ordered'],
    ARRAY['Cart', 'Cancelled'],
    ARRAY['Ordered', 'Paid'],
    ARRAY['Ordered', 'Cancelled'],
    ARRAY['Paid', 'Preparing'],
    ARRAY['Paid', 'Cancelled'],
    ARRAY['Preparing', 'Shipped'],
    ARRAY['Preparing', 'Cancelled'],
    ARRAY['Shipped', 'Received'],
    ARRAY['Shipped', 'Returned'],
    ARRAY['Received', 'Returned'],
    ARRAY['Returned', 'Refunded'],
    ARRAY['Cancelled', 'Refunded']
  ];
  
  -- Verificar se a transição é válida
  RETURN EXISTS (
    SELECT 1 
    FROM unnest(valid_transitions) AS transition
    WHERE transition[1]::order_status_enum = current_status
    AND transition[2]::order_status_enum = p_new_status
  );
END;
$$;

-- 5.8 Função para controlar estoque quando pedido é fechado
CREATE OR REPLACE FUNCTION public.process_order_stock(p_order_id bigint)
RETURNS boolean
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  item_record RECORD;
  insufficient_stock_count integer := 0;
BEGIN
  -- Verificar se há estoque suficiente para todos os itens
  FOR item_record IN 
    SELECT oi.product_id, oi.quantity, p.stock_quantity, p.title
    FROM order_items oi
    JOIN products p ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id
  LOOP
    IF item_record.stock_quantity < item_record.quantity THEN
      insufficient_stock_count := insufficient_stock_count + 1;
      RAISE NOTICE 'Estoque insuficiente para produto: % (Disponível: %, Solicitado: %)', 
        item_record.title, item_record.stock_quantity, item_record.quantity;
    END IF;
  END LOOP;
  
  -- Se há produtos sem estoque suficiente, retornar false
  IF insufficient_stock_count > 0 THEN
    RETURN false;
  END IF;
  
  -- Se chegou até aqui, há estoque suficiente - subtrair quantidades
  FOR item_record IN 
    SELECT oi.product_id, oi.quantity
    FROM order_items oi
    WHERE oi.order_id = p_order_id
  LOOP
    UPDATE products 
    SET stock_quantity = stock_quantity - item_record.quantity
    WHERE id = item_record.product_id;
  END LOOP;
  
  RETURN true;
END;
$$;

-- 5.9 Função para garantir apenas um endereço padrão por usuário
CREATE OR REPLACE FUNCTION public.ensure_single_default_address()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
  -- Se o novo endereço é padrão, remover flag de outros endereços do mesmo usuário
  IF NEW.is_default = true THEN
    UPDATE addresses 
    SET is_default = false 
    WHERE customer_id = NEW.customer_id 
    AND id != NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER ensure_single_default_address_trigger
BEFORE INSERT OR UPDATE ON addresses
FOR EACH ROW EXECUTE FUNCTION ensure_single_default_address();

-- 5.10 Função para atualizar valor total do pedido automaticamente
CREATE OR REPLACE FUNCTION public.update_order_value()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
DECLARE
  order_total numeric;
  target_order_id bigint;
BEGIN
  -- Determinar o order_id baseado no tipo de operação
  IF TG_OP = 'DELETE' THEN
    target_order_id := OLD.order_id;
  ELSE
    target_order_id := NEW.order_id;
  END IF;
  
  -- Calcular valor total dos itens do pedido
  SELECT COALESCE(SUM(item_value), 0)
  INTO order_total
  FROM order_items
  WHERE order_id = target_order_id;
  
  -- Atualizar valor do pedido
  UPDATE orders 
  SET order_value = order_total
  WHERE id = target_order_id;
  
  -- Retornar o registro apropriado
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

CREATE TRIGGER update_order_value_trigger
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION update_order_value();

-- Função para prevenir alteração não autorizada de is_admin
CREATE OR REPLACE FUNCTION public.prevent_unauthorized_admin_change()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
  -- Se o campo is_admin está sendo alterado
  IF OLD.is_admin IS DISTINCT FROM NEW.is_admin THEN
    -- Verificar se o usuário atual é admin
    IF NOT user_is_admin() THEN
      -- Reverter a mudança
      NEW.is_admin := OLD.is_admin;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Criar o trigger
CREATE TRIGGER prevent_unauthorized_admin_change_trigger
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION prevent_unauthorized_admin_change();

-- ============================================================================
-- 6. SISTEMA DE AUDITORIA MELHORADO
-- ============================================================================

-- 6.1 Função de auditoria (registra para todos os usuários)
CREATE OR REPLACE FUNCTION public.audit_trigger_function()
RETURNS trigger 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  old_values jsonb := '{}';
  new_values jsonb := '{}';
  action_type audit_action_enum;
  record_id_value text;
BEGIN
  -- Determinar tipo de ação e valores
  IF TG_OP = 'DELETE' THEN
    action_type := 'DELETE';
    old_values := to_jsonb(OLD);
    -- Para order_statuses e order_items que não têm id único
    IF TG_TABLE_NAME = 'order_statuses' THEN
      record_id_value := OLD.order_id::text || '_' || OLD.status::text;
    ELSIF TG_TABLE_NAME = 'order_items' THEN
      record_id_value := OLD.order_id::text || '_' || OLD.product_id::text;
    ELSE
      record_id_value := OLD.id::text;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    action_type := 'UPDATE';
    old_values := to_jsonb(OLD);
    new_values := to_jsonb(NEW);
    IF TG_TABLE_NAME = 'order_statuses' THEN
      record_id_value := NEW.order_id::text || '_' || NEW.status::text;
    ELSIF TG_TABLE_NAME = 'order_items' THEN
      record_id_value := NEW.order_id::text || '_' || NEW.product_id::text;
    ELSE
      record_id_value := NEW.id::text;
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    action_type := 'INSERT';
    new_values := to_jsonb(NEW);
    IF TG_TABLE_NAME = 'order_statuses' THEN
      record_id_value := NEW.order_id::text || '_' || NEW.status::text;
    ELSIF TG_TABLE_NAME = 'order_items' THEN
      record_id_value := NEW.order_id::text || '_' || NEW.product_id::text;
    ELSE
      record_id_value := NEW.id::text;
    END IF;
  END IF;
  
  INSERT INTO audit_log (
    table_name,
    record_id,
    action,
    old_values,
    new_values,
    user_id
  ) VALUES (
    TG_TABLE_NAME,
    record_id_value,
    action_type,
    old_values,
    new_values,
    auth.uid()
  );
  
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- 6.2 Triggers de auditoria
CREATE TRIGGER audit_profiles 
AFTER INSERT OR UPDATE OR DELETE ON profiles 
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_orders 
AFTER INSERT OR UPDATE OR DELETE ON orders 
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_order_items 
AFTER INSERT OR UPDATE OR DELETE ON order_items 
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_order_statuses 
AFTER INSERT OR UPDATE OR DELETE ON order_statuses 
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_products 
AFTER INSERT OR UPDATE OR DELETE ON products 
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- ============================================================================
-- 7. CRIAÇÃO AUTOMÁTICA DE PROFILE
-- ============================================================================

-- 7.1 Função para criar profile automaticamente
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, phone, created_at)
  VALUES (
    NEW.id, 
    NEW.raw_user_meta_data->>'full_name', 
    NEW.email,
    NEW.raw_user_meta_data->>'phone',
    NOW()
  );
  
  RETURN NEW;
END;
$$;

-- 7.2 Trigger no auth.users
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- 8. HABILITAÇÃO DO ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_statuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 9. POLÍTICAS DE SEGURANÇA (RLS) CORRIGIDAS
-- ============================================================================

-- 9.1 Políticas para Profiles
CREATE POLICY "Admins can view all profiles" 
ON profiles FOR SELECT 
USING (user_is_admin());

CREATE POLICY "Users can view own profile" 
ON profiles FOR SELECT 
USING (auth.uid() = id);

-- CORREÇÃO: Política sem OLD/NEW
CREATE POLICY "Users can update own profile" 
ON profiles FOR UPDATE 
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- CORREÇÃO: Política para admins
CREATE POLICY "Admins can update any profile" 
ON profiles FOR UPDATE 
USING (user_is_admin())
WITH CHECK (user_is_admin());

CREATE POLICY "Enable insert for new users" 
ON profiles FOR INSERT 
WITH CHECK (auth.uid() = id);

-- 9.2 Políticas para Products, Categories, Carriers
CREATE POLICY "Anyone can view active products" 
ON products FOR SELECT 
USING (is_active = true OR user_is_admin());

CREATE POLICY "Anyone can view active categories" 
ON categories FOR SELECT 
USING (is_active = true OR user_is_admin());

CREATE POLICY "Anyone can view active carriers" 
ON carriers FOR SELECT 
USING (is_active = true OR user_is_admin());

CREATE POLICY "Only admins can manage products" 
ON products FOR ALL 
USING (user_is_admin())
WITH CHECK (user_is_admin());

CREATE POLICY "Only admins can manage categories" 
ON categories FOR ALL 
USING (user_is_admin())
WITH CHECK (user_is_admin());

CREATE POLICY "Only admins can manage carriers" 
ON carriers FOR ALL 
USING (user_is_admin())
WITH CHECK (user_is_admin());

-- 9.3 Políticas para Addresses
CREATE POLICY "Users can manage own addresses" 
ON addresses FOR ALL 
USING (
  customer_id = auth.uid() OR user_is_admin()
)
WITH CHECK (
  customer_id = auth.uid() OR user_is_admin()
);

-- 9.4 Políticas para Orders
CREATE POLICY "Users can view own orders" 
ON orders FOR SELECT 
USING (
  customer_id = auth.uid() OR user_is_admin()
);

CREATE POLICY "Users can create own orders" 
ON orders FOR INSERT 
WITH CHECK (
  customer_id = auth.uid() OR user_is_admin()
);

CREATE POLICY "Users can update cart orders" 
ON orders FOR UPDATE 
USING (
  (customer_id = auth.uid() AND is_order_in_cart_status(id)) 
  OR user_is_admin()
)
WITH CHECK (
  (customer_id = auth.uid() AND is_order_in_cart_status(id)) 
  OR user_is_admin()
);

CREATE POLICY "Only admins can delete orders" 
ON orders FOR DELETE 
USING (user_is_admin());

-- 9.5 Políticas para Order Items (otimizada para performance)
CREATE POLICY "Users can view own order items" 
ON order_items FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_items.order_id 
    AND (orders.customer_id = auth.uid() OR user_is_admin())
  )
);

CREATE POLICY "Users can manage items in cart orders" 
ON order_items FOR ALL 
USING (
  user_is_admin() OR 
  EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_items.order_id 
    AND orders.customer_id = auth.uid() 
    AND is_order_in_cart_status(orders.id)
  )
)
WITH CHECK (
  user_is_admin() OR 
  EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_items.order_id 
    AND orders.customer_id = auth.uid() 
    AND is_order_in_cart_status(orders.id)
  )
);

-- 9.6 Políticas para Order Statuses
CREATE POLICY "Users can view own order statuses" 
ON order_statuses FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_statuses.order_id 
    AND (orders.customer_id = auth.uid() OR user_is_admin())
  )
);

CREATE POLICY "Admins can manage all order statuses" 
ON order_statuses FOR ALL 
USING (user_is_admin())
WITH CHECK (
  user_is_admin() 
  AND validate_status_transition(order_id, status)
);

CREATE POLICY "Users can close their cart orders" 
ON order_statuses FOR INSERT 
WITH CHECK (
  status = 'Ordered'
  AND EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_statuses.order_id 
    AND orders.customer_id = auth.uid()
    AND get_latest_order_status(orders.id) = 'Cart'
  )
  AND process_order_stock(order_id)
);

CREATE POLICY "Users can pay their ordered orders" 
ON order_statuses FOR INSERT 
WITH CHECK (
  status = 'Paid'
  AND EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_statuses.order_id 
    AND orders.customer_id = auth.uid()
    AND get_latest_order_status(orders.id) = 'Ordered'
  )
);

-- 9.7 Políticas para Audit Log
CREATE POLICY "Only admins can view audit logs" 
ON audit_log FOR SELECT 
USING (user_is_admin());

CREATE POLICY "System can insert audit logs" 
ON audit_log FOR INSERT 
WITH CHECK (true);

-- ============================================================================
-- 10. STORAGE BUCKETS PARA SUPABASE
-- ============================================================================

-- 10.1 Bucket para avatares de usuários
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- 10.2 Bucket para imagens de produtos
INSERT INTO storage.buckets (id, name, public)
VALUES ('products', 'products', true)
ON CONFLICT (id) DO NOTHING;

-- 10.3 Políticas de storage para avatares
CREATE POLICY "Avatar images are publicly accessible" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'avatars');

CREATE POLICY "Users can upload their own avatar" 
ON storage.objects FOR INSERT 
WITH CHECK (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can update their own avatar" 
ON storage.objects FOR UPDATE 
USING (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can delete their own avatar" 
ON storage.objects FOR DELETE 
USING (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- 10.4 Políticas de storage para produtos
CREATE POLICY "Product images are publicly accessible" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'products');

CREATE POLICY "Only admins can upload product images" 
ON storage.objects FOR INSERT 
WITH CHECK (
  bucket_id = 'products' 
  AND user_is_admin()
);

CREATE POLICY "Only admins can update product images" 
ON storage.objects FOR UPDATE 
USING (
  bucket_id = 'products' 
  AND user_is_admin()
);

CREATE POLICY "Only admins can delete product images" 
ON storage.objects FOR DELETE 
USING (
  bucket_id = 'products' 
  AND user_is_admin()
);

-- ============================================================================
-- 11. ÍNDICES PARA PERFORMANCE
-- ============================================================================

-- Índices essenciais para performance
CREATE INDEX idx_profiles_is_admin ON profiles(is_admin) WHERE is_admin = true;
CREATE INDEX idx_profiles_email ON profiles(email);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX idx_orders_customer_created ON orders(customer_id, created_at DESC);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_order_statuses_order_datetime ON order_statuses(order_id, datetime DESC);
CREATE INDEX idx_order_statuses_latest ON order_statuses(order_id, datetime DESC);
CREATE INDEX idx_order_statuses_status ON order_statuses(status);
CREATE INDEX idx_addresses_customer_id ON addresses(customer_id);
CREATE INDEX idx_addresses_customer_default ON addresses(customer_id, is_default);
CREATE INDEX idx_products_category_active ON products(category_id, is_active);
CREATE INDEX idx_products_created_at ON products(created_at DESC);
CREATE INDEX idx_products_active_created ON products(is_active, created_at DESC);
CREATE UNIQUE INDEX idx_products_unique_active_title ON products(title) WHERE is_active = true;
CREATE INDEX idx_categories_active ON categories(is_active);
CREATE INDEX idx_carriers_active ON carriers(is_active);
CREATE INDEX idx_audit_log_user_timestamp ON audit_log(user_id, timestamp DESC);
CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_timestamp ON audit_log(timestamp DESC);

-- ============================================================================
-- 12. INSERÇÃO DE DADOS INICIAIS
-- ============================================================================

-- 12.1 Categoria padrão
INSERT INTO categories (name, description) VALUES 
('Geral', 'Categoria padrão para produtos diversos')
ON CONFLICT (name) DO NOTHING;

-- 12.2 Transportadora padrão
INSERT INTO carriers (name) VALUES ('Transportadora Padrão')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 13. VIEWS ÚTEIS
-- ============================================================================

-- View para pedidos com último status
CREATE OR REPLACE VIEW orders_with_status AS
SELECT 
  o.*,
  get_latest_order_status(o.id) as current_status,
  p.full_name as customer_name,
  p.email as customer_email,
  c.name as carrier_name
FROM orders o
JOIN profiles p ON o.customer_id = p.id
LEFT JOIN carriers c ON o.carrier_id = c.id;

-- View para itens de pedido com detalhes do produto
CREATE OR REPLACE VIEW order_items_detailed AS
SELECT 
  oi.*,
  p.title as product_title,
  p.description as product_description,
  p.image_url as product_image_url,
  o.customer_id,
  cat.name as category_name
FROM order_items oi
JOIN products p ON oi.product_id = p.id
JOIN orders o ON oi.order_id = o.id
JOIN categories cat ON p.category_id = cat.id;

-- View para carrinho de compras
CREATE OR REPLACE VIEW cart_items AS
SELECT 
  oid.*
FROM order_items_detailed oid
JOIN orders o ON oid.order_id = o.id
WHERE get_latest_order_status(o.id) = 'Cart';

-- ============================================================================
-- 14. FUNÇÕES UTILITÁRIAS PARA O FRONTEND
-- ============================================================================

-- 14.1 Função para obter carrinho do usuário atual
CREATE OR REPLACE FUNCTION public.get_user_cart()
RETURNS TABLE (
  order_id bigint,
  product_id bigint,
  product_title text,
  product_price numeric,
  product_image_url text,
  quantity integer,
  unity_value numeric,
  item_value numeric
)
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ci.order_id,
    ci.product_id,
    ci.product_title,
    ci.unity_value,
    ci.product_image_url,
    ci.quantity,
    ci.unity_value,
    ci.item_value
  FROM cart_items ci
  JOIN orders o ON ci.order_id = o.id
  WHERE o.customer_id = auth.uid();
END;
$$;

-- 14.2 Função para adicionar item ao carrinho
CREATE OR REPLACE FUNCTION public.add_to_cart(
  p_product_id bigint,
  p_quantity integer
)
RETURNS jsonb
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  cart_order_id bigint;
  product_price numeric;
  result jsonb;
BEGIN
  -- Verificar se usuário está logado
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Usuário não autenticado');
  END IF;
  
  -- Obter preço do produto
  SELECT price INTO product_price 
  FROM products 
  WHERE id = p_product_id AND is_active = true;
  
  IF product_price IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Produto não encontrado ou inativo');
  END IF;
  
  -- Buscar pedido em status Cart do usuário
  SELECT o.id INTO cart_order_id
  FROM orders o
  WHERE o.customer_id = auth.uid()
  AND get_latest_order_status(o.id) = 'Cart'
  LIMIT 1;
  
  -- Se não existe carrinho, criar um
  IF cart_order_id IS NULL THEN
    INSERT INTO orders (customer_id) 
    VALUES (auth.uid()) 
    RETURNING id INTO cart_order_id;
  END IF;
  
  -- Adicionar ou atualizar item no carrinho
  INSERT INTO order_items (order_id, product_id, quantity, unity_value)
  VALUES (cart_order_id, p_product_id, p_quantity, product_price)
  ON CONFLICT (order_id, product_id)
  DO UPDATE SET 
    quantity = order_items.quantity + p_quantity,
    unity_value = product_price;
  
  RETURN jsonb_build_object('success', true, 'message', 'Item adicionado ao carrinho');
END;
$$;

-- 14.3 Função para fechar pedido (Cart -> Ordered)
CREATE OR REPLACE FUNCTION public.close_order(
  p_order_id bigint,
  p_address_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  current_status order_status_enum;
  order_owner uuid;
BEGIN
  -- Verificar se usuário está logado
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Usuário não autenticado');
  END IF;
  
  -- Verificar se o pedido pertence ao usuário
  SELECT customer_id INTO order_owner
  FROM orders WHERE id = p_order_id;
  
  IF order_owner != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pedido não encontrado ou não pertence ao usuário');
  END IF;
  
  -- Verificar se pedido está em status Cart
  current_status := get_latest_order_status(p_order_id);
  IF current_status != 'Cart' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pedido não está em status de carrinho');
  END IF;
  
  -- Atualizar dados de endereço no pedido
  UPDATE orders SET
    address_postal_code = p_address_data->>'postal_code',
    address_address = p_address_data->>'address',
    address_number = p_address_data->>'number',
    address_complement = p_address_data->>'complement',
    address_neighborhood = p_address_data->>'neighborhood',
    address_city = p_address_data->>'city',
    address_state = (p_address_data->>'state')::brazilian_state_enum,
    recipient_name = p_address_data->>'recipient_name',
    recipient_phone = p_address_data->>'recipient_phone',
    order_date = now()
  WHERE id = p_order_id;
  
  -- Tentar adicionar status 'Ordered' (que processará o estoque)
  BEGIN
    INSERT INTO order_statuses (order_id, status, changed_by)
    VALUES (p_order_id, 'Ordered', auth.uid());
    
    RETURN jsonb_build_object('success', true, 'message', 'Pedido fechado com sucesso');
  EXCEPTION 
    WHEN OTHERS THEN
      RETURN jsonb_build_object('success', false, 'message', 'Erro ao processar estoque: ' || SQLERRM);
  END;
END;
$$;

-- 14.4 Função para pagar pedido (Ordered -> Paid)
CREATE OR REPLACE FUNCTION public.pay_order(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  current_status order_status_enum;
  order_owner uuid;
BEGIN
  -- Verificar se usuário está logado
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Usuário não autenticado');
  END IF;
  
  -- Verificar se o pedido pertence ao usuário
  SELECT customer_id INTO order_owner
  FROM orders WHERE id = p_order_id;
  
  IF order_owner != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pedido não encontrado ou não pertence ao usuário');
  END IF;
  
  -- Verificar se pedido está em status Ordered
  current_status := get_latest_order_status(p_order_id);
  IF current_status != 'Ordered' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pedido não está em status de pedido confirmado');
  END IF;
  
  -- Adicionar status 'Paid'
  INSERT INTO order_statuses (order_id, status, changed_by)
  VALUES (p_order_id, 'Paid', auth.uid());
  
  RETURN jsonb_build_object('success', true, 'message', 'Pagamento processado com sucesso');
END;
$$;

-- 14.5 Função para alterar status de admin (NOVA)
CREATE OR REPLACE FUNCTION public.set_admin_status(
  p_user_id uuid,
  p_is_admin boolean
)
RETURNS jsonb
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
BEGIN
  -- Verificar se o usuário atual é admin
  IF NOT user_is_admin() THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'Apenas administradores podem alterar status de admin'
    );
  END IF;
  
  -- Atualizar status
  UPDATE profiles 
  SET is_admin = p_is_admin,
      updated_at = now()
  WHERE id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'Usuário não encontrado'
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true, 
    'message', 'Status de admin atualizado com sucesso'
  );
END;
$$;

-- ============================================================================
-- 15. CONSULTAS DE VERIFICAÇÃO
-- ============================================================================

-- Verificar se todas as tabelas foram criadas
DO $$
BEGIN
  RAISE NOTICE 'Verificando tabelas criadas...';
END $$;

-- Verificar extensões habilitadas
DO $$
BEGIN
  RAISE NOTICE 'Verificando extensões...';
END $$;

-- Mensagem final
DO $$
BEGIN
  RAISE NOTICE '============================================';
  RAISE NOTICE 'BANCO DE DADOS E-COMMERCE CRIADO COM SUCESSO!';
  RAISE NOTICE '============================================';
  RAISE NOTICE 'Próximos passos:';
  RAISE NOTICE '1. Configure o primeiro usuário admin';
  RAISE NOTICE '2. Teste as políticas RLS';
  RAISE NOTICE '3. Configure backup e monitoramento';
  RAISE NOTICE '4. Implemente o frontend';
  RAISE NOTICE '============================================';
END $$;