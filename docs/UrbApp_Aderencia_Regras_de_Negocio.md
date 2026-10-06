# Aderência às regras de negócio do UrbApp

Data da revisão: 5 de outubro de 2026.

Fonte de verdade: `UrbApp_Especificacao_Mestre_Final_Claude.md`. O protótipo do Figma Make (React/Tailwind) foi usado apenas como referência visual e de interação; onde ele diverge da especificação, a especificação prevalece. O produto continua sendo o aplicativo Flutter com Supabase/PostgreSQL.

As regras críticas são aplicadas no PostgreSQL (funções transacionais, constraints, triggers, RLS e privilégios por coluna). A interface Flutter não é a única barreira de autorização.

## 1. Auditoria: divergências encontradas e correção

### Backend

| # | Divergência encontrada | Risco | Correção |
|---|---|---|---|
| 1 | Cron diário `urbapp-expiracao-diaria` expirava relatos (`expired`) e havia um fluxo paralelo de validação por relato (`request_post_resolution`, `vote_post_resolution`). | A resolução não dependia só da validação comunitária da ocorrência (spec §44). | Cron e funções removidos; tabelas `post_resolution_*` congeladas (leitura apenas para admin); `expired` bloqueado por constraint e status dos relatos sincronizados com a ocorrência. |
| 2 | Cliente podia inserir, alterar e excluir `posts` diretamente. | Status, contadores e vínculos forjados; caminho para desanonimizar relatos via órgão. | Escritas diretas revogadas em todas as tabelas e views; relatos só nascem pelas RPCs de ocorrência. |
| 3 | `problem_categories`, `activity_events` e `user_devices` sem RLS. | Leitura e escrita irrestritas. | RLS ativado com políticas mínimas. |
| 4 | `post_status_history.changed_by` e `resolution_cycles.initiated_by` legíveis. | Identificação de autores anônimos. | Privilégios por coluna; `get_active_resolution_cycle` devolve apenas `initiated_by_me`. |
| 5 | Perfis podiam alterar XP, pontos e papéis pelo cliente. | Fraude de gamificação. | Atualização restrita a nome, usuário, avatar, biografia, cidade e insígnia em destaque. |
| 6 | Apoios e comentários ligados ao relato, não à ocorrência. | Contagem duplicada e conversa fragmentada (spec: a ocorrência é a entidade central). | `occurrence_supports` e `comments.occurrence_id` com backfill; colaboradores não apoiam a própria ocorrência; respostas limitadas a um nível. |
| 7 | Cidades e categorias novas ficavam sem gestão vigente e sem órgão responsável. | Ocorrências sem vínculo institucional. | Provisionamento automático (gestão e órgão "não reivindicados") e validação do vínculo cidade → gestão → órgão. |
| 8 | Métricas de órgão contavam a mesma ocorrência mais de uma vez e incluíam casos fora da competência municipal. | Indicadores distorcidos. | Views refeitas: apenas competência municipal, crédito ao órgão atual, herança por troca de gestão e crédito parlamentar só com ação concreta durante o acompanhamento. |
| 9 | Evidência de resolução sem verificação. | Ciclos abertos com fotos inexistentes. | Evidência obrigatória configurável por categoria e conferência da existência do objeto no Storage. |
| 10 | Mídia de relatos anônimos listável no Storage. | Desanonimização pelo caminho do arquivo. | Upload em `reports/<post_id>/`, listagem só do dono, exclusão só nos primeiros 15 minutos. |
| 11 | Ranking da cidade incluía relatos anônimos. | Vínculo indireto entre autor e relato anônimo. | `get_city_ranking` exclui relatos anônimos. |
| 12 | Notificações ignoravam preferências e repetiam eventos. | Ruído e eventos duplicados. | `notification_preferences` por categoria e eventos sem duplicidade (`report_added`, `status_changed`). |
| 13 | Ações institucionais sem os tipos `received`, `progress_update` e `observation`; conclusão durante validação abria outro ciclo. | Linha do tempo incompleta e ciclos concorrentes. | Tipos adicionados e transições ajustadas: uma ocorrência resolvida só aceita observação ou posicionamento oficial. |
| 14 | Textos de negócio sem acentuação nas mensagens, na linha do tempo e nas notificações. | Interface com grafia incorreta. | Funções recriadas com a grafia correta e registros existentes atualizados. |

### Frontend

| Divergência | Correção |
|---|---|
| Identidade visual anterior, diferente do protótipo aprovado. | Novo design system (`UrbColors`, `UrbText` com Manrope, raios, ícones SVG do Figma) e todas as telas migradas. |
| Navegação diferente da spec. | `Início · Buscar · Relatar · Transparência · Perfil`; Alertas no sino com contador. |
| Feed baseado em relatos. | Feed, busca e mapa baseados em ocorrências (`occurrence_feed_rows`, `search_occurrences`, `get_trending_occurrences`). |
| Workspace do vereador do Figma não aprovado (spec §44). | Workspace derivado das telas aprovadas (detalhe, transparência e listas), sem rankings ou notas políticas. |
| "+15 pontos" no Figma. | Valor da spec: +50 pontos por contribuição útil. |
| Telas legadas (feed, post, indicadores antigos, moderação antiga). | Removidas e substituídas pelas novas telas. |

## 2. Migrações criadas nesta revisão

| Migração | Conteúdo |
|---|---|
| `20261005010000_retire_legacy_resolution_and_expiration.sql` | Remove expiração diária e validação por relato; constraints de status oficial. |
| `20261005011000_harden_client_privileges.sql` | Revoga escritas diretas, ativa RLS, privilégios por coluna e políticas de Storage. |
| `20261005012000_occurrence_social_layer.sql` | Apoios, comentários, preferências de notificação, views de feed/comentários, busca e moderação de comentários. |
| `20261005013000_integrity_privacy_and_provisioning.sql` | Privacidade de autoria, provisionamento institucional, auditoria de status, pontos por ocorrência e evidência por categoria. |
| `20261005014000_institutional_actions_and_metrics.sql` | Ações institucionais e parlamentares, métricas, contexto de resolução, validações próximas e contribuições do perfil. |
| `20261005015000_points_notification_copy.sql` | Texto da notificação de pontos. |
| `20261005016000_portuguese_backend_copy.sql` | Acentuação de mensagens, eventos, notificações e nomes provisórios. |
| `20261005017000_participation_and_city_rankings.sql` | Ranking de cidadãos (geral e do mês) só com perfis públicos e não institucionais, e posição pessoal. |
| `20261005018000_gamification_integrity.sql` | Cidade de origem em cada transação de pontos/XP, ranking pela cidade da ação, XP de relato uma vez por cidadão e ocorrência, remoção dos triggers legados de `post_supports` e de funções órfãs. |
| `20261005019000_city_profile_and_resolution_ranking.sql` | Fuso horário IANA por cidade, universo elegível da cidade, métricas contínuas da cidade (estados separados, mediana pela última resolução, média complementar), histórico de gestões e ranking de cidades por taxa e tempo de resolução com amostra mínima configurável. |
| `20261006010000_require_photo_for_new_occurrence.sql` | Nova ocorrência exige ao menos 1 foto (até 4) e descrição com 10+ caracteres, validadas no servidor: a foto sobe antes para `reports/pending/` e `publish_occurrence_report` a vincula ao primeiro relato na mesma transação. A função antiga deixa de ser chamável pelo cliente. Relato adicional segue sem foto obrigatória. |

## 3. Mapeamento de status

| Banco (`report_status`) | Especificação | Rótulo no app |
|---|---|---|
| `open` | ABERTO | Aberto |
| `in_analysis` | EM_ANALISE | Em análise |
| `in_progress` | EM_ANDAMENTO | Em andamento |
| `awaiting_validation` | AGUARDANDO_VALIDACAO | Aguardando validação |
| `completed` | RESOLVIDO | Resolvido |
| `reopened` | REABERTO | Reaberto |
| `closed` | ENCERRADO | Encerrado (não representa resolução) |

`expired` permanece no enum apenas por compatibilidade e é bloqueado por constraint.

## 4. Cobertura funcional

| Área | Implementação |
|---|---|
| Ocorrência x relato | Uma ocorrência agrega vários relatos; criação e associação são transacionais. |
| Duplicidade | Busca por cidade, categoria, proximidade e texto; o cidadão decide entre associar ou criar; a moderação consolida depois sem perder histórico. |
| Vínculo institucional | Toda ocorrência recebe cidade, gestão vigente e órgão conforme a responsabilidade configurada. |
| Validação comunitária | 3 confirmações, raio de 5 km, prazo de 72 h, 2 rejeições e espera de 24 h, todos configuráveis; um voto por usuário; quem informa não vota; expiração não resolve. |
| Reabertura | Exige descrição e nova evidência; preserva ciclos e eventos anteriores. |
| Gestão municipal | Períodos independentes, troca de gestão, ocorrências herdadas e indicadores por período. |
| Órgãos | Perfis não reivindicados, verificados e participantes; encaminhamento automático; ações oficiais com evidência opcional. |
| Vereadores | Perfil verificado e acompanhamento voluntário com ações públicas, sem ranking ou nota política. |
| Competência | Casos municipais, estaduais, federais, concessionárias, privados ou desconhecidos; casos externos não entram nas métricas municipais. |
| Anonimato | Apenas público: o autor e a moderação veem a autoria; os demais veem "Relato anônimo". |
| Gamificação | Pontos (ranking) e XP (nível) separados e registrados em `xp_transactions` com tipo, origem, cidade e data. Contribuição (+50 pontos, +20 XP) e resolução (+100 pontos, +50 XP) valem uma vez por cidadão e ocorrência, igual para quem inicia e para quem adiciona relato; apoio (+15) e comentário (+5) recebidos vão para quem iniciou a ocorrência; estorno por moderação. |
| Notificações | Preferências por categoria e alertas agrupados por período, com contador em tempo real. |
| Ranking (§22, §39) | Página "Rankings" com as duas categorias juntas e com o mesmo peso: prévia de Cidades (taxa de resolução, top 3 e situação da cidade) e de Cidadãos (top 3 e posição do usuário), cada uma com acesso à lista completa. Entradas: Transparência › Rankings (seção única) e Perfil › posição (lista de cidadãos). Cidades usa taxa e mediana do tempo de resolução, sem score composto; Cidadãos usa pontos atribuídos à cidade da ação. Nenhum ranking de agentes políticos, gestões ou órgãos. |
| Cidade (§33, §44.6) | A Transparência é a visão pública e contínua da cidade: panorama, indicadores detalhados sob demanda (estados, mediana e média, evolução por mês de criação, categorias, bairros), ocorrências, Gestão vigente, órgãos, vereadores, comparação entre cidades e participação. A mesma tela abre para qualquer cidade a partir do comparativo (com voltar). A Gestão Municipal mantém tela própria com as métricas do mandato e o histórico de gestões. Troca de gestão não reinicia a cidade. |
| Ranking de cidades | Universo: ocorrências únicas de competência municipal, sem duplicatas absorvidas e sem invalidação (encerramento administrativo segue como não resolvido). Taxa = resolvidas hoje ÷ elegíveis × 100. Tempo = mediana entre a criação e a última transição para RESOLVIDO; reabertas atuais ficam fora. "Geral" = criadas desde o início; "Este mês" = coorte criada desde o início do mês no fuso da cidade. Amostra mínima em `city_ranking_settings` (10 ocorrências para taxa, 5 resoluções para tempo); abaixo dela a cidade aparece sem posição. Desempate: taxa → mais ocorrências → nome; tempo → mais resoluções → nome. |
| Acesso institucional | Atalho no login para vereadores, órgãos e gestão: o cadastro já registra o papel desejado e, após o primeiro acesso, o app abre a solicitação com cidade e e-mail preenchidos. As funções só são liberadas após verificação. |

## 5. Verificação automatizada

- `npx supabase db reset`: todas as migrações e o seed aplicados do zero.
- `npx supabase test db`: 191 testes pgTAP (`occurrence_business_rules_test.sql`, `occurrence_social_and_security_test.sql`, `gamification_ranking_test.sql` e `city_ranking_test.sql`).
- `npx supabase db lint --local --schema public --level warning`: sem erros.
- `dart analyze`: sem problemas.
- `flutter test`: 69 testes de domínio, regras, widgets e navegação (`navigation_test.dart`).

## 6. Dados locais de demonstração

`supabase/seed.sql` é aplicado só no ambiente local (`db reset`). Todas as contas usam a senha `urbapp123`:

| Conta | Papel |
|---|---|
| `cidadao@urbapp.test` | Cidadão (Gabriel Alves) |
| `mariana@urbapp.test`, `rafael@urbapp.test`, `camila@urbapp.test` | Cidadãos |
| `vereadora@urbapp.test` | Vereadora verificada |
| `saae@urbapp.test` | Órgão participante (SAAE) |
| `prefeitura@urbapp.test` | Gestão municipal |
| `admin@urbapp.test` | Administração da plataforma |
| `lucas@urbapp.test`, `beatriz@urbapp.test` | Cidadãos de Campinas |
| `pedro@urbapp.test`, `julia@urbapp.test` | Cidadãos de Belo Horizonte |
| `tiago@urbapp.test` | Cidadão de Recife |

Campinas, Belo Horizonte e Recife recebem ocorrências e moradores próprios para demonstrar o ranking de cidadãos em outras cidades.

O seed vincula uma foto a todas as ocorrências (`reports/<post_id>/evidencia-<id>.jpg`); os arquivos (`supabase/seed-media/`) são enviados ao bucket `post-images` local por `bash supabase/seed-media.sh`, depois de `supabase db reset`. Nas categorias sem imagem própria (árvore, calçada, semáforo e demais cidades) as fotos são reaproveitadas apenas como demonstração.

## 7. Ressalvas conhecidas

- O login com Google depende de habilitar o provedor no Supabase.
- A localização usada na validação é informada pelo dispositivo; não há prova de presença física além do raio.
- A troca de gestão move as ocorrências abertas no momento em que é executada.
- A reabertura segue as regras da spec (descrição e nova evidência), sem critérios adicionais de elegibilidade.
- O título curto em Relatar é opcional (spec §3.1); sem título, o app gera um a partir da categoria e do local.
- Exportação de dados, 2FA e exclusão de conta não aparecem em Configurações até existir backend para eles.
- **Apoio e comentário recebidos vão para quem iniciou a ocorrência.** O modelo liga apoios e comentários à ocorrência, não a um relato específico; por isso não há distribuição entre relatores (evita inflar pontos). Relato e resolução já valem o mesmo para quem inicia e para quem contribui depois.
- **Fuso horário por cidade** preenchido pela UF; cidades em microrregiões com fuso próprio (oeste do AM e do PA, Fernando de Noronha) precisam de ajuste explícito em `cities.timezone`. O ranking de cidadãos ainda usa o horário de Brasília para o mês.
- **`post_supports` mantida como histórico**, sem triggers; o cliente só tem leitura.

## 8. Etapas de publicação

1. Autenticar a Supabase CLI e aplicar as migrações no projeto vinculado (o seed não deve ir para o remoto).
2. Definir ao menos um usuário em `platform_user_roles` como `admin` por um processo operacional seguro.
3. Executar smoke tests no remoto com contas de cidadão, gestão, órgão, vereador e moderação.
4. Gerar e publicar o build web com as variáveis do ambiente final.
5. Monitorar erros, políticas RLS e os primeiros ciclos de validação após o lançamento.
