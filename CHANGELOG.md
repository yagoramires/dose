# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] - 2026-10-25

### Adicionado
- Instalação pelo NeyHub (`Dose-0.2.0.neyplugin`): o Dose roda dentro dele, com os mesmos dados, e os lembretes chegam como NeyHub.
- Instalador `.dmg` e atualização automática no avulso: baixa sozinho e troca o app quando você fecha o Dose (ou em **Reiniciar agora**), com a janela **Novidades** na abertura seguinte.
- Tela do Dose (modo Janela no avulso e tela dentro do NeyHub): abas Hoje (agenda do dia, quando precisar, contadores e últimos 7 dias), Histórico (14 dias por item, sequência, rodízio de local e registros) e Itens (lista com o formulário ao lado).
- Dentro do NeyHub, tocar num lembrete abre a tela do Dose (em "Escolher local…", já no registro do item); com o Dose só na barra de menus, abre o popover.
- Configurações (em **Itens e ajustes → Configurações…**): onde o Dose aparece (janela com ícone no Dock, barra de menus ou os dois, sem reiniciar) e o estado das notificações.

### Alterado
- Visual no tema Grafite (escuro, acento verde-limão), com a mesma navegação de antes.
- Se o NeyHub já roda o Dose, o avulso avisa, sai dos itens de login e fecha.
- O build exige o certificado "Aero Local Signing" (sem assinatura ad-hoc).
- `dados.json` ganha o campo `schema`. Um arquivo de versão mais nova, ou que não abre, fica só leitura com aviso: o Dose não grava por cima (antes, um arquivo ilegível virava um vazio depois da cópia).
- Menu **Editar** do avulso: desfazer, recortar, copiar, colar e selecionar tudo (`⌘Z`, `⌘X`, `⌘C`, `⌘V`, `⌘A`) nos campos de texto.

## [0.1.0] - 2026-10-22

### Adicionado
- Primeira versão: controle de remédios e suplementos pela barra de menus, começando vazio.
- Vários horários por dia, com a cápsula que enche a cada dose e lembrete na hora de cada uma.
- Frequência todo dia, por dias da semana ou a cada N dias.
- Uma vez por semana com o local da última aplicação num mapa do corpo, sugerindo o rodízio.
- Quando precisar, só com registro e contagem do dia.
- Contadores de dias sem, com barra até o recorde.
- Cor por item e cápsula como botão de marcar.
- Lembretes que insistem a cada 2 h até marcar, com "Tomei" e adiar 30 min direto na notificação.
- Histórico com registro em outro horário e exclusão de registro errado.
