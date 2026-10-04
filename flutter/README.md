# UrbApp Flutter

Aplicativo cliente do UrbApp. As regras críticas ficam no Supabase; o Flutter apresenta os fluxos, coleta evidências e usa as RPCs autorizadas.

## Configuração

Crie `dart_defines/dev.json` a partir de `dart_defines/dev.json.example` e informe `SUPABASE_URL` e `SUPABASE_ANON_KEY`. Esse arquivo é local e não deve ser enviado ao Git.

## PowerShell

```powershell
cd C:\Users\gabri\Desktop\urbapp-repository\flutter
flutter pub get
flutter run -d web-server --web-port 7357 --dart-define-from-file=dart_defines/dev.json
```

Durante a execução, use `r` para hot reload, `R` para hot restart e `q` para encerrar.

## Qualidade

```powershell
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test
flutter build web --dart-define-from-file=dart_defines/dev.json
```
