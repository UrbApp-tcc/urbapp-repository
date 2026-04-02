# Colocar o projeto no GitHub

## 1. Criar o repositório no GitHub

1. Acesse **https://github.com/new**
2. **Repository name:** `urbapp-flutter` (ou outro nome, ex: `meu_app`)
3. Deixe **Private** ou **Public**, como preferir
4. **Não** marque "Add a README", "Add .gitignore" nem "Choose a license" (o projeto já tem esses arquivos)
5. Clique em **Create repository**

## 2. Conectar e enviar o código

No terminal, na pasta do projeto, rode (troque **SEU_USUARIO** pelo seu usuário do GitHub):

```bash
git remote add origin https://github.com/SEU_USUARIO/urbapp-flutter.git
git branch -M main
git push -u origin main
```

Se quiser manter a branch `primeira-versao` no GitHub:

```bash
git remote add origin https://github.com/SEU_USUARIO/urbapp-flutter.git
git push -u origin primeira-versao
```

**Exemplo** (usuário `jhordanbandeira`):

```bash
git remote add origin https://github.com/jhordanbandeira/urbapp-flutter.git
git push -u origin primeira-versao
```

## 3. Autenticação

Ao dar `git push`, o GitHub pode pedir login:

- **Senha:** use um **Personal Access Token** (não a senha da conta)
- Criar token: GitHub → Settings → Developer settings → Personal access tokens → Generate new token (com permissão `repo`)

Ou use **GitHub Desktop** / **Git Credential Manager** para guardar o login.
