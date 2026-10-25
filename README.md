# Dose

Controle de remédios e suplementos pela barra de menus do macOS. Um clique na pílula mostra o que falta hoje, o que já foi tomado (e a que horas) e o que é "quando precisar".

![Dose](docs/print.png)

O print usa itens de exemplo.

## Instalar

Hoje a instalação é por build local (veja **Build local**): rode `scripts/setup-signing.sh` uma vez e depois `scripts/build.sh --run`.

Instalador `.dmg` e instalação pelo NeyHub chegam na próxima versão.

## Permissões

- **Notificações**: para os lembretes (alerta e som). O macOS pede na primeira vez.
- Não pede Acessibilidade, Gravação de Tela, Câmera nem Microfone, e não usa a rede.

## Como usar

Clique na pílula na barra de menus.

- Começa vazio: você adiciona e configura cada item (nome, dose, frequência, horários, cor).
- **Vários horários por dia** (08:00 e 20:00 = 2 doses): a cápsula enche a cada dose e o lembrete vem na hora de cada uma.
- **Todo dia** (vitamina C, vitamina D): marca com um clique, mostra a hora em que tomou e quantos dias seguidos.
- **Dias da semana** (só sábado, ou seg/qua/sex…) e **a cada N dias** (ômega 3 a cada 3 dias), contando da última dose.
- **Uma vez por semana** (Medicação semanal): dia fixo, avisa se atrasou e pede o **local da aplicação** num mapa do corpo (braço, abdômen, coxa; esquerdo e direito), sugerindo o local usado há mais tempo pro rodízio e mostrando onde foi a última aplicação. Tomar um dia antes também conta.
- **Quando precisar** (chá, café): só registra, com contagem do dia.
- **Contadores** ("12 dias sem comer doce"): dias desde a última vez e uma barra até o seu recorde. "+ Novo contador" no fim da seção, ↺ zera, ⋯ registra outra data ou desfaz.
- Clicar no nome de um item abre a edição dele; o + no topo cria um item novo.
- Cada item tem uma cor de cápsula, escolhida na edição; a cápsula vira o botão de marcar (meio cheia = falta, cheia com ✓ = tomado).
- **Lembretes**: no horário marcado, só se ainda não tomou. Insiste a cada 2 h (das 7 h às 23 h) até marcar. Dá pra marcar "Tomei" ou adiar 30 min direto na notificação.
- A pílula na barra mostra quantos itens ainda faltam hoje.
- Histórico com tudo o que foi registrado, dá pra apagar um registro errado ou registrar com outro horário.

Os dados ficam em `~/Library/Application Support/Dose/dados.json` e o log em `~/Library/Logs/Dose/dose.log`.

## Atalhos

O Dose não tem atalho global. Nos formulários, Return confirma e Esc cancela.

## Modos de exibição

A pílula na barra mostra quantos itens ainda faltam hoje. A interface segue o claro ou escuro do macOS. Cada item tem uma cor de cápsula, escolhida na edição.

## Atualizações

O Dose ainda não se atualiza sozinho: para atualizar, baixe o código novo e rode o build de novo (veja **Build local**).

## Build local

Precisa só das Command Line Tools (sem Xcode).

```sh
scripts/setup-signing.sh   # uma vez: certificado local de assinatura
scripts/build.sh --run     # compila, assina e abre build/Dose.app
```

`build/Dose.app/Contents/MacOS/Dose --snapshots <pasta>` desenha cada tela em PNG com dados de exemplo, sem tocar nos dados de verdade.

> O SDK atual transformou `@State` num macro cujo plugin só vem com o Xcode; as telas usam `@ViewState` (em `Views/Root.swift`), que faz a mesma coisa.

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE)
