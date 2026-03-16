# Bubu Cloud Personal for macOS

Este pacote e a release separada do projeto para macOS.

## O que muda nesta release

- usa scripts `.command`
- nao depende de `pwsh`
- baixa binarios nativos de `File Browser` e `cloudflared`
- usa `~/CloudDrive` por padrao

## Scripts

- `start-cloud.command`: sobe a stack
- `stop-cloud.command`: derruba a stack
- `status-cloud.command`: mostra status e URL ativa
- `open-cloud.command`: abre a tela de upload
- `install-deps.command`: baixa as dependencias antes do primeiro start

## Requisitos

- `python3`
- `curl`
- `tar`
- macOS com permissao para executar `.command`

## Uso rapido

1. Dê permissão de execução se necessário:
   `chmod +x *.command common.sh`
2. Rode `./start-cloud.command`
3. Acompanhe a URL mostrada no terminal
4. Abra `./open-cloud.command` quando quiser cair direto na tela de upload
