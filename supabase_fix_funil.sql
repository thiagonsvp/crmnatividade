-- Corrige o trigger de timestamp que hoje tenta escrever em NEW.updated_at
-- mesmo em tabelas que usam a coluna "update".
CREATE OR REPLACE FUNCTION public.atualizar_update_timestamp()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF to_jsonb(NEW) ? 'updated_at' THEN
    NEW := jsonb_populate_record(NEW, jsonb_build_object('updated_at', NOW()));
  END IF;

  IF to_jsonb(NEW) ? 'update' THEN
    NEW := jsonb_populate_record(NEW, jsonb_build_object('update', NOW()));
  END IF;

  RETURN NEW;
END;
$$;

-- Garante que novos atendimentos nascam na primeira etapa do funil.
ALTER TABLE public.crm_atendimentos
  ALTER COLUMN etapa_funil SET DEFAULT 'Lead';

-- Normaliza registros antigos para as novas etapas.
UPDATE public.crm_atendimentos
SET etapa_funil = CASE etapa_funil
  WHEN 'Prospecto' THEN 'Lead'
  WHEN 'Qualificado' THEN 'Atendimento'
  WHEN 'Fechado' THEN 'Ganho'
  ELSE etapa_funil
END
WHERE etapa_funil IN ('Prospecto', 'Qualificado', 'Fechado')
   OR etapa_funil IS NULL;

-- Preenche atendimentos sem etapa.
UPDATE public.crm_atendimentos
SET etapa_funil = 'Lead'
WHERE etapa_funil IS NULL;

-- Permissões usadas pelo app via REST/anon key.
GRANT SELECT, INSERT, UPDATE ON public.crm_atendimentos TO anon, authenticated;

-- Se RLS estiver ativo, estas policies permitem o kanban atualizar/criar atendimentos.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'crm_atendimentos'
      AND policyname = 'crm_atendimentos_insert_anon'
  ) THEN
    EXECUTE 'CREATE POLICY crm_atendimentos_insert_anon ON public.crm_atendimentos FOR INSERT TO anon, authenticated WITH CHECK (true)';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'crm_atendimentos'
      AND policyname = 'crm_atendimentos_update_anon'
  ) THEN
    EXECUTE 'CREATE POLICY crm_atendimentos_update_anon ON public.crm_atendimentos FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true)';
  END IF;
END $$;
