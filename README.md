# Dose

Controle de remédios e suplementos pela barra de menus do macOS. Um clique na pílula mostra o que falta hoje, o que já foi tomado (e a que horas) e o que é "quando precisar".

- **Todo dia** (vitamina C, vitamina D): marca com um clique, mostra a hora em que tomou e quantos dias seguidos.
- **Uma vez por semana** (Medicação semanal): dia fixo, avisa se atrasou e pede o **local da aplicação** num mapa do corpo (braço, abdômen, coxa; esquerdo e direito), sugerindo o local usado há mais tempo pro rodízio. Tomar um dia antes também conta.
- **Quando precisar** (chá, café): só registra, com contagem do dia.
- **Lembretes**: no horário marcado, só se ainda não tomou. Insiste a cada 2 h (das 7 h às 23 h) até marcar. Dá pra marcar "Tomei" ou adiar 30 min direto na notificação.
- A pílula na barra mostra quantos itens ainda faltam hoje.
- Histórico com tudo o que foi registrado, dá pra apagar um registro errado ou registrar com outro horário.

Os dados ficam em `~/Library/Application Support/Dose/dados.json` e o log em `~/Library/Logs/Dose/dose.log`.

## Compilar

Precisa só das Command Line Tools (sem Xcode).

```sh
scripts/setup-signing.sh   # uma vez: certificado local (o mesmo do Aero e do Capture)
scripts/build.sh --run     # compila, assina e abre build/Dose.app
```

`build/Dose.app/Contents/MacOS/Dose --snapshots <pasta>` desenha cada tela em PNG com dados de exemplo, sem tocar nos dados de verdade.

> O SDK atual transformou `@State` num macro cujo plugin só vem com o Xcode; as telas usam `@ViewState` (em `Views/Root.swift`), que faz a mesma coisa.

## Licença

MIT
