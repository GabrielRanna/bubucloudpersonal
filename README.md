# Bubu Cloud Personal

Transforme um HD comum em uma nuvem pessoal acessivel pela internet, com interface web, upload com progresso e administracao simples em Windows, com uma release separada para macOS.

## O que este projeto entrega

- navegador de arquivos com `File Browser`
- upload grande com barra de progresso real e envio em partes
- pagina de upload dedicada em `/upload-progress`
- tema claro e escuro na tela de upload
- URL publica exibida em tempo real enquanto a stack roda
- assets do editor Ace servidos localmente, sem depender de CDN
- rename que preserva extensao de arquivo
- cadastro e login funcionando com senha publica amigavel, mesmo com as regras rigidas internas do `File Browser`
- release separada para macOS com scripts `.command`

## Por que isso e legal

Em vez de deixar um HD de 1 TB parado, a ideia aqui e transformar a maquina em um "Google Drive pessoal":

- voce acessa seus arquivos pelo navegador
- faz upload de qualquer PC ou celular
- acompanha o progresso de arquivos grandes
- mantem controle local sobre os dados

## Stack

- `File Browser`: interface principal de arquivos
- `cloudflared`: exposicao publica da maquina
- `gateway.py`: proxy, autenticao publica, upload customizado e correcoes de UX
- `public-url-monitor.ps1`: monitor visual da URL publica
- scripts PowerShell para a stack principal no Windows
- bundle separado de macOS com scripts `.command`

## Arquivos principais

- `start-cloud.ps1`: sobe `File Browser`, gateway, tunnel e monitor
- `stop-cloud.ps1`: derruba a stack inteira
- `status-cloud.ps1`: mostra status local e publico
- `install-deps.ps1`: baixa `File Browser` e `cloudflared` para a stack Windows
- `gateway.py`: proxy local + pagina de upload + ajustes do frontend
- `public-url-monitor.ps1`: janela que exibe a URL publica ativa
- `cloud-common.ps1`: configuracoes compartilhadas e arquivos de status
- `macos-release/`: bundle base da release separada de macOS
- `build-macos-release.ps1`: monta uma pasta pronta para publicar a release de macOS

## Como usar

1. Tenha `PowerShell` e `Python` instalados
2. Execute `start-cloud.ps1`
3. Na primeira vez, a stack baixa as dependencias automaticamente
4. Abra a URL local ou publica exibida pelo monitor
5. Entre com o usuario configurado
6. Use a raiz do `File Browser` para navegar
7. Use `/upload-progress` para uploads grandes com barra de progresso

## Release de macOS

- o macOS agora sai como release separada
- essa release usa scripts `.command`
- ela nao depende de `pwsh`
- o bundle fica em `macos-release/` e pode ser montado em `dist/` via `build-macos-release.ps1`
- o caminho padrao dos arquivos no Mac e `~/CloudDrive`

## Como montar a release de macOS

1. Rode `build-macos-release.ps1`
2. Pegue a pasta gerada em `dist/BubuCloudPersonal-macos`
3. No Mac, rode `start-cloud.command`
4. Se preferir baixar as dependencias antes, rode `install-deps.command`

## Destaques de implementacao

- uploads grandes sao enviados em partes de `1 MB` para evitar travamentos na URL publica
- o gateway corrige pontos praticos do `File Browser` sem precisar manter um fork completo
- o login publico do admin e simples para uso diario, mas o backend continua usando credenciais fortes
- o cadastro de usuarios traduz senhas normais para senhas internas seguras
- o projeto agora tem distribuicao separada para Windows e macOS

## Limites atuais

- a URL `trycloudflare` muda quando o tunnel reinicia
- o PC precisa ficar ligado e com a sessao ativa
- o acesso fixo ideal ainda seria com dominio proprio ou `DDNS + port forwarding`

## Status do projeto

Projeto funcional e em uso real, com foco em:

- experiencia melhor no navegador
- uploads mais confiaveis
- setup simples no Windows
- release dedicada para macOS
- menos atrito para uso pessoal no dia a dia
