# Aderência às regras de negócio do UrbApp

Data da revisão: 4 de outubro de 2026.

Este documento rastreia a implementação em relação a `UrbApp_Regras_de_Negocio_Final.md`. As regras críticas são aplicadas no PostgreSQL por funções transacionais, constraints, triggers e RLS; a interface Flutter não é a única barreira de autorização.

## Cobertura funcional

| Área | Implementação |
|---|---|
| Ocorrência x relato | Uma ocorrência urbana agrega vários relatos; criação e associação são transacionais. |
| Duplicidade | Busca por cidade, categoria, proximidade e texto; cidadão decide entre associar ou criar; moderação pode consolidar depois sem perder histórico. |
| Vínculo institucional | Toda ocorrência municipal recebe cidade, gestão vigente e órgão conforme responsabilidade configurada. |
| Máquina de estados | `open`, `in_analysis`, `in_progress`, `awaiting_validation`, `completed`, `reopened` e `closed`, com transições protegidas no backend. |
| Validação comunitária | Quórum, rejeições, raio, prazo e cooldown configuráveis; snapshot por ciclo; um voto por usuário; iniciador não vota; expiração não resolve automaticamente. |
| Reabertura | Exige descrição e nova evidência; preserva ciclos e eventos anteriores. |
| Gestão municipal | Períodos independentes, troca de gestão, ocorrências herdadas e indicadores preservados por período. |
| Órgãos | Perfis não reivindicados/verificados/participantes, encaminhamento automático, mudança de responsabilidade com histórico e ações oficiais com evidência opcional. |
| Vereadores | Perfil verificado, acompanhamento voluntário independente, ações públicas, espera por retorno, encerramento e resolução durante acompanhamento. |
| Competência | Casos municipais, estaduais, federais, concessionárias, privados ou desconhecidos; casos externos não distorcem métricas municipais. |
| Indicadores | Cidade, gestão, órgão e vereador; contagem por ocorrência, tempos, taxas e distinção entre cálculo automático e ação oficial. |
| Moderação | Fila auditável, procedente/improcedente, ocultação, invalidação integral e reversão de pontos diretamente fraudulentos. |
| Anonimato | Identidade mascarada no backend, colunas sensíveis sem leitura pública, histórico sem ator e proteção de caminhos antigos de mídia. |
| Gamificação | Pontos por contribuição, apoio, comentário, validação e resolução; reversão por fraude; níveis e insígnias existentes. |
| Notificações | Apoio, comentário e eventos de ocorrência para autores e seguidores, incluindo ações institucionais e parlamentares. |
| Governança | Configuração de categorias, órgão responsável, validação, competência, duplicidades, verificação institucional e mudança de gestão. |

## Segurança e rastreabilidade

- A conclusão de cidadão, vereador, Prefeitura ou órgão abre validação; nenhum desses atores resolve sozinho.
- A autoria anônima permanece disponível internamente para segurança e moderação, mas não para cidadãos, vereadores ou perfis institucionais.
- Ações oficiais registram ator, gestão, órgão, data, descrição, previsão/encaminhamento quando aplicável e evidência opcional.
- Mudanças de gestão, órgão e parâmetros mantêm histórico e não reescrevem ciclos anteriores.
- Perfis institucionais só recebem permissão após solicitação e revisão administrativa.

## Verificação automatizada

- `supabase db reset`: todas as migrações aplicadas do zero.
- `supabase test db`: 77 testes pgTAP cobrindo os fluxos e controles críticos.
- `supabase db lint --local --schema public --level warning`: nenhum erro de schema.
- `dart analyze`: nenhum problema no aplicativo Flutter.
- `flutter test` e `flutter build web`: devem ser executados com o servidor de desenvolvimento encerrado, pois o Flutter usa um lock global do SDK.

## Etapas de publicação

Antes de considerar o ambiente remoto publicado:

1. autenticar a Supabase CLI e aplicar as migrações no projeto vinculado;
2. definir ao menos um usuário em `platform_user_roles` como `admin` por processo operacional seguro;
3. executar smoke tests no remoto com contas de cidadão, gestão, órgão, vereador e moderação;
4. gerar e publicar o build web com as variáveis do ambiente final;
5. monitorar erros, políticas RLS e os primeiros ciclos de validação após o lançamento.
