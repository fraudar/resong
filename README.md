<div align="center">

# resong

**Player de musica multiplataforma open-source, leve e standalone.**

Um unico app Flutter com motor local embutido em Dart para Windows, Linux, Android e iOS. Sem servidor externo, sem banco remoto e sem configuracao complicada.

![Plataformas](https://img.shields.io/badge/Plataformas-Windows%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-111318?style=flat-square)
![Flutter](https://img.shields.io/badge/Flutter-3.47%2B-02569B?style=flat-square)
![Dart](https://img.shields.io/badge/Dart-3.13%2B-0175C2?style=flat-square)
![Licenca](https://img.shields.io/badge/Licenca-MIT-2ea44f?style=flat-square)

[Downloads](#downloads) | [Recursos](#recursos) | [Arquitetura](#arquitetura) | [Estrutura](#estrutura) | [Compilar do zero](#compilar-do-zero)

</div>

---

## Downloads

| Plataforma | Formato | Onde encontrar | Observacao |
| :--- | :--- | :--- | :--- |
| Windows (x64) | Instalador (`.exe`) | `releases/resong-windows-x64.exe` | Instala em Programas, cria atalhos e desinstalador |
| Linux (x64) | `.deb` e `.tar.gz` (CI) | [.github/workflows/build-linux.yml](.github/workflows/build-linux.yml) | Compila pacote Debian e portatil em `ubuntu-latest` |
| Android | Pacote APK (`.apk`) | `releases/resong-android.apk` | Instalacao direta no aparelho |
| iOS | IPA via macOS / CI | [.github/workflows/build-ios.yml](.github/workflows/build-ios.yml) | Compila `.ipa` em runner `macos-latest` |

> [!NOTE]
> Builds nativos de Linux (`.deb`/`.tar.gz`) e iOS (`.ipa`) exigem seus respectivos sistemas/toolchains (Linux com GTK3/libmpv e macOS com Xcode). Ao subir este repositorio no GitHub, os workflows em `.github/workflows/` compilam ambos os pacotes automaticamente na nuvem.

---

## Recursos

### Motor local e fontes de midia
- **Standalone em Dart:** busca, resolucao de audio, letras e proxy HTTP `Range`/HLS rodam em loopback (`127.0.0.1`) dentro do proprio aplicativo.
- **Provedores nativos:** YouTube Music, SoundCloud, Audius e Internet Archive integrados sem chaves obrigatorias.
- **Spotify opcional:** suporte a busca, ISRC e catalogos configurando credenciais em **Configuracoes -> Fontes -> Spotify** ou colando links publicos.
- **Addons BitChord:** adicione, reordene e verifique a saude de fontes externas compativeis direto pelo app.

### Interface Desktop e Mobile
- **Modo Desktop (`>= 860px`):** layout limpo inspirado no Sonora com barra lateral fixa, menu de conta no avatar, barra inferior com controle de volume ao passar o mouse (hover/mute) e player expandido com paineis laterais de Letras, Fila e Equalizador.
- **Modo Mobile (`< 860px`):** mini-player flutuante, barra de navegacao em vidro fosco (Liquid Glass), controle por gestos e transicoes com fisica spring (*Flight*).
- **Perfis de Artista:** acesso rapido clicando no nome do artista pela musica atual, listas ou player, exibindo populares, discografia e catalogo completo.

### Audio e Letras
- **Efeitos de audio:** equalizador de 5 bandas, som 8D, Bass Boost, Gapless e Normalizacao de volume (`just_audio` + `media_kit` no Windows e Linux; `audio_service` com controles de notificacao no Android e audio em background no iOS).
- **Letras sincronizadas:** ranking multi-fonte combinando LyricsPlus, NetEase (YRC/LRC), LRCLIB, YouTube Music e Addons, com suporte a modo **Karaoke** (palavra por palavra), **Vocal de fundo**, **Romanizacao** e **Traducao**.

### Offline e Privacidade
- **Downloads com tags:** faixas salvas localmente com metadados e capa embutidos direto no arquivo MP3/MP4 (`AudioTags`).
- **Inicio resiliente offline:** sem internet ou com o feed remoto indisponivel, a tela inicial exibe banner de modo offline junto com downloads prontos, recentes, curtidas e suas playlists locais.
- **Perfil simples e sem rastros externos:** usa apenas Nome de exibicao, bio e foto local (sem login ou `@usuario`), modo **Perfil privado** e limpeza imediata em **Configuracoes -> Privacidade -> Limpar historico de escutas**.

---

## Arquitetura

```text
+-------------------------------------------------------------------+
|                           UI (Flutter)                            |
|     Desktop (Sonora layout)  |  Mobile (Liquid Glass + Pill)      |
+-------------------------------------------------------------------+
                 |                                |
                 v                                v
+------------------------------+   +--------------------------------+
|     Riverpod State Layer     |   |      Audio Playback Layer      |
| Library, Fx, Scrobbles, DL   |   |  just_audio + media_kit / iOS  |
+------------------------------+   +--------------------------------+
                 |
                 v  HTTP loopback (127.0.0.1:porta)
+-------------------------------------------------------------------+
|               LocalEngineServer (Dart Embutido)                   |
|                                                                   |
|  - Catalogo & Busca: YT Music, SoundCloud, Spotify, Audius, IA    |
|  - Proxy Stream:     Range (206), reescrita HLS e pre-aquecimento |
|  - Letras:           LRCLIB, LyricsPlus, NetEase, YTM, Traducao   |
|  - Addons:           Protocolo BitChord (consumidor e produtor)   |
|  - Banco Local:      resong_store.json (playlists, favs, matches) |
+-------------------------------------------------------------------+
```

---

## Estrutura

```text
resong/
|-- .github/
|   +-- workflows/
|       |-- build-ios.yml           # Build automatizado de IPA sem assinatura (macOS)
|       +-- build-linux.yml         # Build automatizado de .deb e .tar.gz (Ubuntu)
|-- app/
|   |-- lib/
|   |   |-- core/                   # Cliente HTTP Api, DTOs, tema, paleta, tags ID3/MP4
|   |   |-- engine/                 # Motor Dart local (fontes, letras, resolver e proxy)
|   |   |-- screens/                # Home, Busca, Biblioteca, Detalhe, Perfil, Config, Players
|   |   |-- state/                  # Controllers Riverpod, player, downloads, efeitos, historico
|   |   +-- widgets/                # Artwork, Glass, WaveSeekBar, HoverVolumeControl, LyricsPanel
|   |-- test/                       # Testes unitarios e de widget
|   |-- android/                    # Projeto Android (Kotlin/Gradle) + icones adaptativos
|   |-- ios/                        # Projeto iOS (Runner, AppIcon, Info.plist)
|   |-- linux/
|   |   +-- packaging/              # Icone PNG, .desktop e install.sh para Linux
|   +-- windows/
|       +-- installer/
|           +-- resong.iss          # Script oficial do instalador Inno Setup 6
|-- releases/                       # Instaladores e binarios prontos para distribuicao
|-- .gitignore
|-- LICENSE                         # Licenca MIT
+-- README.md
```

---

## Compilar do zero

### Requisitos
- **Flutter:** 3.47+ (Dart 3.13+)
- **Windows Desktop:** Visual Studio Build Tools 2022 (Desktop development with C++) + Windows 10/11 SDK + Inno Setup 6 (opcional, para gerar o instalador)
- **Linux Desktop:** Clang, CMake, Ninja, `pkg-config`, `libgtk-3-dev`, `liblzma-dev` e `libmpv-dev`
- **Android APK:** Android SDK + Java 17 ou 21
- **iOS IPA:** macOS + Xcode + CocoaPods

### Desenvolvimento e testes

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

Para executar em modo de desenvolvimento:

```bash
flutter run -d windows
flutter run -d linux
flutter run -d android
```

<details>
<summary>Comandos para gerar os builds de release</summary>

```bash
cd app

# Windows (bundle portatil .exe + DLLs)
flutter build windows --release

# Windows (instalador unico Setup.exe com Inno Setup 6)
iscc windows/installer/resong.iss

# Linux (bundle desktop - executar em Linux)
flutter build linux --release

# Android (.apk)
flutter build apk --release

# iOS (.ipa - executar em macOS)
flutter build ios --release --no-codesign
# ou pacote assinado para distribuicao:
flutter build ipa --release
```

</details>

---

## Licenca

Distribuido sob a licenca [MIT](LICENSE).
Este projeto e independente e nao possui afiliacao com YouTube, SoundCloud, Spotify, Audius ou Internet Archive.
