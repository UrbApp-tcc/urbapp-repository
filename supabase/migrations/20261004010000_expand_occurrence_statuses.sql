-- Status adicionais do modelo consolidado de ocorrencias.
-- Mantemos os valores legados para compatibilidade durante a migracao do app.
alter type public.report_status add value if not exists 'awaiting_validation';
alter type public.report_status add value if not exists 'reopened';
