# Personal Cloud

Setup local para uma nuvem pessoal em Windows com:

- `File Browser` para navegacao de arquivos
- `cloudflared` para exposicao publica temporaria
- `gateway.py` para upload com barra de progresso e envio em partes
- monitor visual da URL publica em tempo real

## Arquivos principais

- `start-cloud.ps1`: sobe File Browser, gateway, tunnel e monitor
- `stop-cloud.ps1`: derruba a stack inteira
- `status-cloud.ps1`: mostra status local/publico
- `gateway.py`: proxy local + pagina de upload com progresso
- `public-url-monitor.ps1`: janela que mostra a URL publica enquanto a stack roda

## Observacoes

- O projeto usa arquivos locais que nao entram no Git, como binarios, logs, PID files e credenciais.
- A URL `trycloudflare` e temporaria e pode mudar ao reiniciar o tunnel.
- Para uso fixo em producao, o ideal e trocar para um dominio proprio ou DDNS + port forwarding.

# bubucloudpersonal
