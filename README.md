# DualMonRaspiOS-win

**Raspberry Pi как второй монитор для Windows 10 по сети** — для случаев, когда он нужен не всегда:
перетащил окна, поработал, выключил. Без постоянной настройки и без «зеркала» рабочего стола.

> **English, in short.** Use the screen of a Raspberry Pi 4 (Raspberry Pi OS Trixie, labwc/Wayland) as an *extended*
> second monitor of a Windows 10 PC over the LAN. Windows creates a virtual display
> ([Apollo](https://github.com/ClassicOldSong/Apollo)), the Pi shows it through
> [Moonlight Qt](https://github.com/moonlight-stream/moonlight-qt). A tray icon on Windows turns it on/off and
> switches between the Windows screen and the Pi desktop; windows dragged to the second monitor are
> auto-pinned so they stay put when you switch Windows virtual desktops. Includes auto-reconnect,
> address lists that survive router changes, and doctor scripts for both sides. Docs below are in Russian.

## Как это работает

```
Windows 10                                   Raspberry Pi 4
┌───────────────────────────┐   LAN/Wi-Fi    ┌─────────────────────────────┐
│ Apollo (виртуальный       │ ─────────────► │ Moonlight Qt (полный экран) │
│ монитор + кодирование)    │   видео H.264  │ + скрипты sm-*.sh           │
│                           │                │                             │
│ значок в трее ────────────┼── SSH (ключ, только 4 команды) ─► start/stop/toggle/ping
│ + закрепление окон        │                │ панель Pi прячется на время │
└───────────────────────────┘                │ стрима, возвращается по     │
                                             │ кнопке/сворачиванию         │
                                             └─────────────────────────────┘
```

Что получается:

- второй монитор появляется **только на время стрима** и исчезает вместе с ним; окна перетаскиваются мышью;
- панель задач Windows есть и на втором экране (трей и Quick Launch Windows на дополнительной панели не рисует — ограничение Windows);
- **левый клик по значку в трее** переключает: экран Windows ⇄ рабочий стол Pi (со своей панелью);
- окна на втором мониторе **автоматически закрепляются** «на всех рабочих столах» и не уезжают при смене виртуальных столов;
- после обрыва связи Pi **сама переподключается** и возвращает прежний режим;
- списки адресов (IP/имена) обновляются сами, а при смене роутера добавляются одной строкой; есть диагностика на обеих сторонах.

## Статус и проверенные конфигурации

Собрано и проверено автором на одной связке: Windows 10 Pro 22H2 + GeForce GTX 1050 Ti, Raspberry Pi 4B, Raspberry Pi OS Trixie
(labwc), Wi-Fi 2.4 ГГц. Автовосстановление после обрыва проверено на заглушках, на железе проверка продолжается.
Это не готовый продукт, а рабочий набор скриптов: возможны шероховатости на других конфигурациях. Issues и pull request'ы приветствуются.

## Что понадобится

| Windows | Raspberry Pi |
|---|---|
| Windows 10 (должен работать и 11, не проверялось), Apollo, OpenSSH-клиент (есть по умолчанию), PowerShell 5.1 | Raspberry Pi 4, Trixie с labwc (Wayland), `moonlight-qt`, `wlrctl` (ставит `install-pi.sh`), SSH-сервер |

Аппаратное декодирование на Pi 4 работает для **H.264**, не включай HEVC.

## Быстрый старт

Папку проекта удобно держать **общей** для обеих машин (например, через Syncthing): через неё ходят списки адресов и открытый ключ.
Без общей папки тоже работает — клонируй репозиторий на обе машины и вноси адреса вручную в `hosts/*.manual.txt`,
а файл `keys/windows-*.pub` скопируй на Pi.

**Windows**

1. Установи Apollo: `winget install ClassicOldSong.Apollo --source winget`
   (при ошибке сертификата — скачай установщик со страницы релизов Apollo).
2. Открой `https://localhost:47990` (предупреждение о сертификате — норма) и создай логин и пароль.
   **Логина по умолчанию нет — запиши его.** Забыл — сброс (cmd от администратора):
   `cd /d "C:\Program Files\Apollo"`, `sunshine.exe --creds ЛОГИН ПАРОЛЬ`, перезапуск службы `ApolloService`.
3. В веб-панели Apollo → **Applications → Add New**: Name = `Second Monitor`, команда пустая,
   галочка **Always create Virtual Display** → Save. (Имя должно совпадать с `APP_NAME` в `settings.conf`.)
4. Параметры → Персонализация → Панель задач → «Несколько дисплеев»: показывать панель на всех дисплеях;
   кнопки — «на панели задач, где открыто окно».
5. Дважды кликни **`install-windows.bat`** (ключ SSH, модуль `VirtualDesktop`, автозапуск, запуск значка).

**Raspberry Pi**

6. `bash install-pi.sh` (ставит `moonlight-qt` и `wlrctl`, ссылки в `~/bin`, разрешает ключи из `keys/`, ярлыки, таймер адресов).
7. Спаривание (один раз; процесс `moonlight-qt` должен быть закрыт):
   ```
   pkill moonlight-qt
   QT_QPA_PLATFORM=offscreen moonlight-qt pair АДРЕС_WINDOWS 2>&1 | grep -v -E 'DRM|HDMI1|SDL |Qt '
   ```
   PIN введи в веб-панели Apollo (вкладка PIN) и выдай клиенту права. Адрес бери из **локальной сети**, не из ZeroTier/VPN.
8. Проверка: `sm-doctor.sh` на Pi и `doctor-windows.bat` на Windows.
9. По желанию: кнопки на панель Pi — ПКМ по панели → Добавить новые элементы → Лаунчер → «Второй монитор: переключить».

## Повседневная работа

- Значок в трее Windows: **левый клик — переключить**, правый — меню (включить / переключить / выключить, проверка связи, списки адресов, диагностика, окна на втором мониторе).
- Пока на Pi развёрнут экран Windows, мышь и клавиатура Pi управляют Windows (так устроен Moonlight). Чтобы поработать на Pi — переключи.
- Горячие клавиши Moonlight на **физической** клавиатуре Pi: `Ctrl+Alt+Shift+D` свернуть, `+Q` закрыть стрим, `+Z` отпустить/захватить мышь.
- Панель Pi (`xfce4-panel`) на время стрима отключается (иначе просвечивает поверх потока) и возвращается, когда окно свёрнуто.
- Повторное «Включить» безопасно: если стрим уже идёт — ничего не перезапускается, свёрнутое окно возвращается.

### Автовосстановление

После обрыва (Wi‑Fi, перезапуск Apollo и т. п.) Pi переподключается в течение `RECONNECT_MAX_SEC` (по умолчанию 600 с) и возвращает режим
(экран Windows или рабочий стол Pi). Намеренно закрытый стрим («Выключить», `Ctrl+Alt+Shift+Q`) не восстанавливается.
Обрыв определяется по строкам лога Moonlight; сохранятся ли окна на виртуальном мониторе, зависит от поведения Apollo при отключении клиента.

## Адреса и смена сети

Всё в `hosts/`:

| Файл | Кто пишет | Кто читает |
|---|---|---|
| `pi.auto.txt` | Pi (при запуске и раз в 10 минут) | трей Windows |
| `pi.manual.txt` | ты | трей Windows |
| `windows.auto.txt` | трей Windows | Pi |
| `windows.manual.txt` | ты | Pi |

Добавить адрес можно: через меню трея («Изменить адреса Pi» / «Изменить адреса Windows (для Pi)»), на Pi `sm-hosts.sh add АДРЕС`,
или вписать в `*.manual.txt` (по одному в строке, `#` — комментарий; допустимы имена вроде `raspberrypi.local`).
`*.manual.txt` и `*.auto.txt` в git не попадают (в репозитории лежат только шаблоны `*.example.txt`).

## Если «всё установлено, но ничего не работает»

0. Запусти диагностику обеих сторон (`sm-doctor.sh` на Pi, `doctor-windows.bat` на Windows) — она сама подсказывает по пунктам.
1. Машины включены, в одной сети, Windows не спит.
2. **Сменился адрес** (новый роутер, DHCP) — самая частая причина. Адреса: `ipconfig` на Windows, `ip -br a` на Pi → добавь, см. раздел выше.
3. Служба Apollo: `sc query ApolloService` (RUNNING), порт `netstat -ano | findstr :47989`; перезапуск: `net stop ApolloService & net start ApolloService`.
4. Профиль сети Windows «Общедоступная» блокирует входящие: `Set-NetConnectionProfile -InterfaceAlias "<имя>" -NetworkCategory Private`.
5. `Failed to connect` у `moonlight-qt` на Pi — обычно висит старый процесс: `pkill moonlight-qt`.
6. Слетело спаривание — повтори шаг 7. Пропало приложение в Apollo — создай заново (шаг 3).
7. Стрим не стартует — лог на Pi: `grep -v -E 'DRM|HDMI1|FFmpeg' /tmp/sm-start.log | head -40` (прошлый запуск: `.prev`).
8. Нет значка/трей упал — `%APPDATA%\SecondMonitor\tray.log`; `run-tray.bat` запускает заново (страж сам перезапускает трей после сбоя).
9. Трей пишет про ключ — заново `install-windows.bat`, потом `install-pi.sh` (дописывает ключи из `keys/` в `~/.ssh/authorized_keys`).
10. **Аварийные выходы:** на клавиатуре Pi `Ctrl+Alt+Shift+D` (вернётся панель) или `+Q`; трей → «Выключить»; по SSH на Pi `sm-stop.sh`,
    `sm-panel.sh start`; совсем плохо: `pkill moonlight-qt; pkill -f 'sm-start.sh --run'; sm-panel.sh start`.
    Если Apollo считает приложение запущенным — жёлтая кнопка «стоп» на вкладке Applications.

## Особенности

- **60 fps, а не 30:** на 30 курсор Windows рисуется в потоке и двигается рывками. Битрейт: 12000 Кбит/с по LAN, 6000 для адресов вне LAN (`settings.conf`).
- Рабочие столы Windows **общие для всех мониторов**, отдельных столов на монитор система не умеет — поэтому окна второго монитора закрепляются автоматически
  (`windows/second-monitor-pin.ps1`, модуль [VirtualDesktop](https://github.com/MScholtes/PSVirtualDesktop)). Окна без закрепления уезжают вместе со сменой стола;
  чтобы увидеть, какие это окна, — меню трея → «Окна на втором мониторе».
- SSH-ключ без пароля ограничен в `authorized_keys` командами `start / stop / toggle / ping`. Закрытый ключ (`~/.ssh/sm_key`) не копируй и не коммить.
- Если рядом в автозагрузке живёт программа, чистящая значки трея (например TrayIconBuster), она может падать с ошибкой `TB_GETBUTTON failed` при появлении
  виртуального монитора — это не наш трей; программу можно отключить в автозагрузке.

## Состав репозитория

```
install-windows.bat / .ps1   установка стороны Windows
install-pi.sh                установка стороны Pi
run-tray.bat                 запуск значка в трее (скрыто)
doctor-windows.bat           диагностика Windows
settings.conf                разрешение, fps, битрейт, имя приложения, время автовосстановления
windows/                     трей, страж, закрепление окон, диагностики (PowerShell)
pi/                          скрипты Pi: sm-start / sm-stop / sm-toggle / sm-panel / sm-ssh / sm-hosts / sm-doctor
hosts/                       шаблоны списков адресов (рабочие файлы в git не попадают)
keys/                        сюда install-windows.ps1 кладёт открытый ключ (в git не попадает)
publish-github.sh            вспомогательный скрипт публикации (в git не попадает)
```

Логи: Pi — `/tmp/sm-start.log`; Windows — `%APPDATA%\SecondMonitor\tray.log`, `pin.log`.

## Благодарности и лицензия

Построено на [Apollo](https://github.com/ClassicOldSong/Apollo) (форк [Sunshine](https://github.com/LizardByte/Sunshine)),
[Moonlight](https://github.com/moonlight-stream/moonlight-qt), [wlrctl](https://git.sr.ht/~brocellous/wlrctl),
[PSVirtualDesktop](https://github.com/MScholtes/PSVirtualDesktop). Эти проекты не связаны с автором и имеют собственные лицензии.
Скрипты этого репозитория — под лицензией MIT (см. `LICENSE`). Всё поставляется «как есть».
