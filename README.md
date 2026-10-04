# UrbApp

Plataforma comunitária para registrar, acompanhar e validar problemas urbanos. O projeto combina um aplicativo Flutter com Supabase/PostgreSQL e separa explicitamente:

- ocorrências urbanas únicas de relatos individuais;
- execução municipal de acompanhamento parlamentar;
- conclusão informada de resolução confirmada pela comunidade;
- dados calculados de manifestações oficiais.

## Estrutura

```text
flutter/                 aplicativo Flutter (web, Android e iOS)
supabase/migrations/     schema, regras de negócio, RLS e RPCs
supabase/tests/          testes pgTAP das regras críticas
docs/                    arquitetura e rastreabilidade funcional
```

## Executar no PowerShell

Pré-requisitos: Flutter, Node.js, Docker Desktop e Supabase CLI.

```powershell
cd C:\Users\gabri\Desktop\urbapp-repository
npx supabase start
npx supabase db reset

cd flutter
flutter pub get
flutter run -d web-server --web-port 7357 --dart-define-from-file=dart_defines/dev.json
```

Abra `http://127.0.0.1:7357/`. O arquivo `flutter/dart_defines/dev.json` é local e não deve ser versionado. Use o projeto remoto para desenvolvimento integrado ou preencha um arquivo próprio com os valores retornados por `npx supabase status -o env` para testar contra o Supabase local.

## Validar

```powershell
cd C:\Users\gabri\Desktop\urbapp-repository
npx supabase db reset
npx supabase test db
npx supabase db lint --local --schema public --level warning

cd flutter
dart analyze
flutter test
flutter build web --dart-define-from-file=dart_defines/dev.json
```

## Regras de negócio

A matriz de aderência e as decisões técnicas estão em [docs/UrbApp_Aderencia_Regras_de_Negocio.md](docs/UrbApp_Aderencia_Regras_de_Negocio.md).
