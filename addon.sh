#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
#  ██╗  ██╗ ██████╗ ██████╗ ██╗   ██╗██╗██╗      █████╗      🎉 GOD-LEVEL EDITION
#  ╚██╗██╔╝██╔═══██╗██╔══██╗██║   ██║██║██║     ██╔══██╗     White & Orange UI
#   ╚███╔╝ ██║   ██║██████╔╝██║   ██║██║██║     ███████║     Arix Theme Tools
#   ██╔██╗ ██║   ██║██╔══██╗╚██╗ ██╔╝██║██║     ██╔══██║     Auto-Build & Sync
#  ██╔╝ ██╗╚██████╔╝██║  ██║ ╚████╔╝ ██║███████╗██║  ██║     v2.5 Professional
# ==============================================================================

# True-Color & Style Definitions (White & Cyberpunk Orange)
ESC="\033"
WHITE="${ESC}[97m"
BOLD_WHITE="${ESC}[1;97m"
ORANGE="${ESC}[38;5;208m"
GOLD="${ESC}[38;5;214m"
RED="${ESC}[38;5;196m"
GREEN="${ESC}[38;5;46m"
CYAN="${ESC}[38;5;51m"
GRAY="${ESC}[38;5;245m"
DIM="${ESC}[2m"
BOLD="${ESC}[1m"
RESET="${ESC}[0m"

APP_NAME="XORVILA ADDON MANAGER"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null || echo ".")" 2>/dev/null && pwd || pwd)"
PANEL_DIR="${1:-/var/www/pterodactyl}"
ADDON_DIR=""
WORK_DIR=''
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/xorvila-addon-installer-${STAMP}.log"
SELECTED=()

# UI Print Helpers
print_box() {
  local text="$1"
  local color="${2:-$ORANGE}"
  printf "${color}  ┌────────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${color}  │${RESET} ${BOLD_WHITE}%-58s${RESET} ${color}│${RESET}\n" "$text"
  printf "${color}  └────────────────────────────────────────────────────────────┘${RESET}\n"
}

say()   { printf "${ORANGE}[✦ %s]${RESET} ${WHITE}%s${RESET}\n" "$APP_NAME" "$*"; }
ok()    { printf "    ${GREEN}✔${RESET} ${WHITE}%s${RESET}\n" "$*"; }
warn()  { printf "    ${GOLD}⚠${RESET} ${WHITE}%s${RESET}\n" "$*"; }
fail()  { printf "    ${RED}✖${RESET} ${WHITE}%s${RESET}\n" "$*" >&2; }
die()   { fail "$*"; exit 1; }

spinner() {
  local pid=$1
  local message="${2:-Processing}"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  printf "    ${ORANGE}%s${RESET} " "$message"
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 10 ))
    printf "\r    ${ORANGE}%s${RESET} ${WHITE}%s${RESET}" "${spin:$i:1}" "$message"
    sleep 0.1
  done
  printf "\r\033[K"
}

cleanup() { 
  [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; 
}
trap cleanup EXIT
trap 'rc=$?; fail "Installer interrupted at line $LINENO (exit $rc). Check log: $LOG_FILE"; exit "$rc"' ERR

banner() {
  clear
  printf "${ORANGE}"
  printf "    ██╗  ██╗ ██████╗ ██████╗ ██╗   ██╗██╗██╗      █████╗ \n"
  printf "    ╚██╗██╔╝██╔═══██╗██╔══██╗██║   ██║██║██║     ██╔══██╗\n"
  printf "     ╚███╔╝ ██║   ██║██████╔╝██║   ██║██║██║     ███████║\n"
  printf "     ██╔██╗ ██║   ██║██╔══██╗╚██╗ ██╔╝██║██║     ██╔══██║\n"
  printf "    ██╔╝ ██╗╚██████╔╝██║  ██║ ╚████╔╝ ██║███████╗██║  ██║\n"
  printf "    ╚═╝  ╚═╝ ╚═════╝  ╚═╝  ╚═╝  ╚═══╝  ╚═╝╚══════╝╚═╝  ╚═╝\n"
  printf "${RESET}\n"
  printf "${BOLD_WHITE}         ✦ XORVILA PTERODACTYL ADDON MANAGER (ARIX EDITION) ✦         ${RESET}\n"
  printf "${GRAY}         Deep Status Engine • Auto Tools Layout • Production Build    ${RESET}\n\n"
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is missing. Install it and retry."; }

detect_addon_dir() {
  for d in "$SCRIPT_DIR/addons" "$PWD/addons" "$PANEL_DIR/addons" "/root/addons" "/tmp/addons"; do
    if [[ -d "$d" ]]; then
      ADDON_DIR="$d"
      return 0
    fi
  done
  ADDON_DIR="$PANEL_DIR/addons"
}

find_zip() {
  local zip_name="$1"
  for d in "$ADDON_DIR" "$SCRIPT_DIR/addons" "$PWD/addons" "$PANEL_DIR/addons" "$PWD" "$PANEL_DIR" "/root/addons" "/root"; do
    if [[ -n "$d" && -s "$d/$zip_name" ]]; then
      printf '%s' "$d/$zip_name"
      return 0
    fi
  done
  return 1
}

is_addon_files_present() {
  local key="$1"
  local fe="" be=""
  case "$key" in
    blue)
      fe="$PANEL_DIR/resources/scripts/components/server/servercfg/ServerConfigEditor.tsx"
      be="$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/ServerConfigEditorController.php"
      ;;
    plugins)
      fe="$PANEL_DIR/resources/scripts/components/server/mcplugins/PluginsManagerContainer.tsx"
      if [[ -f "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/McPluginsController.php" ]]; then
        be="$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/McPluginsController.php"
      else
        be="$(find "$PANEL_DIR/app/Http/Controllers" -iname "*Plugin*Controller.php" -print -quit 2>/dev/null || true)"
      fi
      ;;
    player)
      fe="$PANEL_DIR/resources/scripts/components/server/players/PlayerManagerContainer.tsx"
      if [[ -f "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/PlayerManagerController.php" ]]; then
        be="$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/PlayerManagerController.php"
      else
        be="$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/PlayerManager/PlayerManagerController.php"
      fi
      ;;
    version)
      fe="$PANEL_DIR/resources/scripts/components/server/versionchanger/VersionChangerContainer.tsx"
      if [[ -f "$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/VersionChanger/VersionChangerController.php" ]]; then
        be="$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/VersionChanger/VersionChangerController.php"
      else
        be="$PANEL_DIR/app/Http/Controllers/Api/Client/Servers/MinecraftVersionController.php"
      fi
      ;;
  esac

  if [[ -n "$fe" && -f "$fe" && -n "$be" && -f "$be" ]]; then
    return 0
  elif [[ ( -n "$fe" && -f "$fe" ) || ( -n "$be" && -f "$be" ) ]]; then
    return 2
  else
    return 1
  fi
}

is_route_linked() {
  local key="$1"
  local rf="$PANEL_DIR/resources/scripts/routers/routes.ts"
  local af="$PANEL_DIR/routes/api-client.php"
  [[ -f "$rf" && -f "$af" ]] || return 1
  case "$key" in
    blue)    grep -q "ServerConfigEditor" "$rf" && grep -q "ServerConfigEditorController" "$af" ;;
    plugins) grep -q "PluginsManagerContainer" "$rf" && grep -qi "plugins" "$af" ;;
    player)  grep -q "PlayerManagerContainer" "$rf" && grep -q "PlayerManagerController" "$af" ;;
    version) grep -q "VersionChangerContainer" "$rf" && grep -q "VersionChangerController" "$af" ;;
  esac
}

is_built_in_assets() {
  local key="$1"
  local assets_dir="$PANEL_DIR/public/assets"
  [[ -d "$assets_dir" ]] || return 1
  case "$key" in
    blue)    grep -Rqs "server-properties" "$assets_dir" 2>/dev/null ;;
    plugins) grep -Rqs "mcplugins" "$assets_dir" 2>/dev/null ;;
    player)  grep -Rqs "PlayerManager" "$assets_dir" 2>/dev/null || grep -Rqs "/players" "$assets_dir" 2>/dev/null ;;
    version) grep -Rqs "version-changer" "$assets_dir" 2>/dev/null ;;
  esac
}

show_addon_status() {
  printf "${ORANGE}  ┌──────────────────────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${ORANGE}  │${RESET} ${BOLD_WHITE}%-27s %-28s %-16s${RESET} ${ORANGE}│${RESET}\n" " ADDON (TOOLS SIDEBAR)" " PANEL STATUS" " BUNDLE"
  printf "${ORANGE}  ├──────────────────────────────────────────────────────────────────────────┤${RESET}\n"

  local items=(
    "plugins|Plugins (/mcplugins)|MC-Plugins-Installer-Addon-Updated.zip"
    "version|Versions (/versions)|Version-Changer-Addon-Updated.zip"
    "blue|Properties (/properties)|Blue-Server-Properties-Addon-Updated.zip"
    "player|Players (/players)|Player-Manager-Addon-Updated.zip"
  )

  for entry in "${items[@]}"; do
    IFS='|' read -r key label zip_name <<< "$entry"
    local p_status="" z_status=""

    if is_addon_files_present "$key"; then
      if is_route_linked "$key"; then
        if is_built_in_assets "$key"; then
          p_status="${GREEN}✔ INSTALLED & BUILT${RESET}"
        else
          p_status="${GOLD}⚠ LINKED (Need Rebuild)${RESET}"
        fi
      else
        p_status="${CYAN}⚠ UPLOADED (Unlinked)${RESET}"
      fi
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then
        p_status="${GOLD}⚠ PARTIAL FILES${RESET}"
      else
        p_status="${RED}✖ NOT FOUND${RESET}"
      fi
    fi

    if find_zip "$zip_name" >/dev/null 2>&1; then
      z_status="${GREEN}✔ Zip Ready${RESET}"
    else
      z_status="${GRAY}No Zip${RESET}"
    fi

    printf "${ORANGE}  │${RESET} ${WHITE}%-27s${RESET} %-36b %-20b ${ORANGE}│${RESET}\n" "  $label" "$p_status" "$z_status"
  done
  printf "${ORANGE}  └──────────────────────────────────────────────────────────────────────────┘${RESET}\n\n"
}

check_panel() {
  [[ -d "$PANEL_DIR" ]] || die "Panel directory not found: $PANEL_DIR"
  [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/routes/api-client.php" && -f "$PANEL_DIR/resources/scripts/routers/routes.ts" ]] || die "'$PANEL_DIR' is not a valid Pterodactyl source root."
  detect_addon_dir
  ok "Pterodactyl root verified: ${WHITE}$PANEL_DIR${RESET}"
  show_addon_status
}

confirm() { 
  local answer; 
  printf "${GOLD}  ?${RESET} ${WHITE}%s [y/N]: ${RESET}" "$1"
  read -r answer; 
  [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]; 
}

prepare_deps() {
  need_cmd php; need_cmd python3
  php -v >/dev/null 2>&1 || die 'PHP runtime failure.'
  [[ -f "$PANEL_DIR/composer.json" ]] || die 'composer.json missing.'
  
  if [[ ! -d "$PANEL_DIR/vendor" ]]; then
    warn "Composer dependencies missing."
    confirm "Run composer install now?" || die 'Cancelled.'
    need_cmd composer
    (cd "$PANEL_DIR" && composer install --no-dev --optimize-autoloader) 2>&1 | tee -a "$LOG_FILE" &
    spinner $! "Installing Composer Packages..."
    ok "Composer packages ready"
  fi

  if [[ ! -d "$PANEL_DIR/node_modules" ]]; then
    warn "Frontend node_modules/ missing."
    if confirm "Install node modules automatically?"; then
      if [[ -f "$PANEL_DIR/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
        (cd "$PANEL_DIR" && yarn install --frozen-lockfile) 2>&1 | tee -a "$LOG_FILE" &
      else
        (cd "$PANEL_DIR" && npm ci) 2>&1 | tee -a "$LOG_FILE" &
      fi
      spinner $! "Installing Frontend Modules..."
      ok "Frontend modules ready"
    else
      die 'Cancelled: Node modules required to build panel.'
    fi
  fi
}

extract_addon() {
  local zip_path="$1" target="$2"
  need_cmd unzip
  mkdir -p "$target"
  unzip -q "$zip_path" -d "$target"
}

install_blue() {
  say 'Processing Blue Server Properties (Properties)...'
  local zip_path=""
  if zip_path="$(find_zip 'Blue-Server-Properties-Addon-Updated.zip')"; then
    local src="$WORK_DIR/blue"
    extract_addon "$zip_path" "$src"
    python3 "$src/install.py" "$PANEL_DIR" 2>&1 | tee -a "$LOG_FILE" || true
  fi

  python3 - "$PANEL_DIR" <<'PY'
from pathlib import Path
import re, sys

root = Path(sys.argv[1])
req_path = root / "app/Http/Requests/Api/Client/Servers/ServerConfigEditorRequest.php"
if not req_path.exists():
    req_path.parent.mkdir(parents=True, exist_ok=True)
    req_path.write_text("""<?php

namespace Pterodactyl\\Http\\Requests\\Api\\Client\\Servers;

use Pterodactyl\\Models\\Permission;
use Pterodactyl\\Http\\Requests\\Api\\Client\\ClientApiRequest;

class ServerConfigEditorRequest extends ClientApiRequest
{
    public function permission(): string
    {
        return Permission::ACTION_FILE_READ_CONTENT;
    }
}
""")

api_file = root / "routes/api-client.php"
s = api_file.read_text()
route_block = """    Route::group(['prefix' => '/server-properties'], function () {
        Route::get('/', [Client\\Servers\\ServerConfigEditorController::class, 'fetch']);
        Route::get('/fetch', [Client\\Servers\\ServerConfigEditorController::class, 'fetch']);
        Route::post('/reset', [Client\\Servers\\ServerConfigEditorController::class, 'fetch']);
        Route::get('/reset', [Client\\Servers\\ServerConfigEditorController::class, 'fetch']);
        Route::post('/', [Client\\Servers\\ServerConfigEditorController::class, 'update']);
        Route::post('/update', [Client\\Servers\\ServerConfigEditorController::class, 'update']);
        Route::put('/update', [Client\\Servers\\ServerConfigEditorController::class, 'update']);
        Route::post('/save', [Client\\Servers\\ServerConfigEditorController::class, 'update']);
        Route::put('/', [Client\\Servers\\ServerConfigEditorController::class, 'update']);
    });"""

if "'/server-properties'" in s:
    s = re.sub(r"[ \t]*Route::group\(\['prefix'\s*=>\s*'/server-properties'\],\s*function\s*\(\)\s*\{[\s\S]*?\}\);", lambda _: route_block, s)
else:
    target = "Route::group(['prefix' => '/settings'], function () {"
    if target in s:
        s = s.replace(target, route_block + "\n\n    " + target, 1)
api_file.write_text(s)

tsx_path = root / "resources/scripts/components/server/servercfg/ServerConfigEditor.tsx"
if tsx_path.exists():
    code = tsx_path.read_text()
    code = code.replace("@/api/server/properties/", "@/api/server/servercfg/")
    code = code.replace("@/components/server/properties/", "@/components/server/servercfg/")
    if "const [formKey, setFormKey]" not in code:
        code = code.replace("const [filterText, setFilterText] = useState('');", "const [filterText, setFilterText] = useState('');\n    const [formKey, setFormKey] = useState(0);")
    code = code.replace("<Formik onSubmit={handleSubmit} initialValues={data.defaults}>", "<Formik key={formKey} enableReinitialize onSubmit={handleSubmit} initialValues={data.defaults}>")
    old_btn = "onClick={() => resetForm()}"
    new_btn = """onClick={() => {
                                        resetForm({ values: data.defaults });
                                        setFormKey((prev) => prev + 1);
                                        mutate();
                                        addFlash({
                                            key: 'servercfg:editor',
                                            type: 'info',
                                            message: 'Changes have been reset to saved server configuration.',
                                        });
                                    }}"""
    if old_btn in code:
        code = code.replace(old_btn, new_btn)
    tsx_path.write_text(code)
PY
  ok 'Properties configured successfully'
}

install_plugins() {
  say 'Processing MC Plugins Installer (Plugins)...'
  local zip_path=""
  if zip_path="$(find_zip 'MC-Plugins-Installer-Addon-Updated.zip')"; then
    local src="$WORK_DIR/plugins"
    extract_addon "$zip_path" "$src"
    bash "$src/install.sh" "$PANEL_DIR" 2>&1 | tee -a "$LOG_FILE" || true
  fi
  ok 'Plugins configured successfully'
}

install_player() {
  say 'Processing Player Manager (Players)...'
  local zip_path=""
  if zip_path="$(find_zip 'Player-Manager-Addon-Updated.zip')"; then
    local src="$WORK_DIR/player"
    extract_addon "$zip_path" "$src"
    (cd "$src" && tar -cf - app resources) | (cd "$PANEL_DIR" && tar -xf -) 2>/dev/null || true
    [[ -f "$src/install-player-manager.sh" ]] && (cd "$PANEL_DIR" && bash "$src/install-player-manager.sh") 2>&1 | tee -a "$LOG_FILE" || true
  fi
  ok 'Players configured successfully'
}

install_version_changer() {
  say 'Processing Version Changer (Versions)...'
  local zip_path=""
  if zip_path="$(find_zip 'Version-Changer-Addon-Updated.zip')"; then
    local src="$WORK_DIR/version-changer"
    extract_addon "$zip_path" "$src"
    python3 - "$PANEL_DIR" "$src" <<'PY'
from pathlib import Path
import shutil, sys
root, src = Path(sys.argv[1]), Path(sys.argv[2])
for rel in ['app/Http/Controllers/Api/Client/Servers/VersionChanger', 'app/Http/Requests/Api/Client/Servers/VersionChanger', 'resources/scripts/components/server/versionchanger']:
    s_item = src / rel
    if s_item.is_dir():
        t_item = root / rel
        t_item.mkdir(parents=True, exist_ok=True)
        for f in s_item.rglob('*'):
            if f.is_file():
                dest = t_item / f.relative_to(s_item)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, dest)
PY
  fi

  python3 - "$PANEL_DIR" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
api = root / 'routes/api-client.php'
text = api.read_text()
vc_routes = """    Route::group(['prefix' => '/version-changer'], function () {
        Route::get('/types', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'types']);
        Route::get('/installed', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'installed']);
        Route::get('/types/{type}', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'versions']);
        Route::get('/types/{type}/{version}', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'builds']);
        Route::post('/install', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'install']);
    });"""
if "'/version-changer'" in text:
    text = re.sub(r"[ \t]*Route::group\(\['prefix'\s*=>\s*'/version-changer'\],\s*function\s*\(\)\s*\{[\s\S]*?\}\);", lambda _: vc_routes, text)
elif 'VersionChangerController::class' not in text:
    target = "Route::group(['prefix' => '/settings'], function () {"
    if target in text:
        text = text.replace(target, vc_routes + "\n\n    " + target, 1)
api.write_text(text)
PY
  ok 'Versions configured successfully'
}

configure_arix_tools_layout() {
  say 'Injecting Arix Tools Section under Management...'
  python3 - "$PANEL_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
routes_file = root / "resources/scripts/routers/routes.ts"
re_file = root / "resources/scripts/routers/RouterElements.tsx"

has_plugins = (root / "resources/scripts/components/server/mcplugins/PluginsManagerContainer.tsx").exists()
has_versions = (root / "resources/scripts/components/server/versionchanger/VersionChangerContainer.tsx").exists()
has_props = (root / "resources/scripts/components/server/servercfg/ServerConfigEditor.tsx").exists()
has_players = (root / "resources/scripts/components/server/players/PlayerManagerContainer.tsx").exists()

imports, tools_routes = [], []
if has_plugins:
    imports.append("import PluginsManagerContainer from '@/components/server/mcplugins/PluginsManagerContainer';")
    tools_routes.append("            {\n                path: '/mcplugins',\n                permission: 'file.*',\n                name: 'Plugins',\n                icon: PuzzleIcon,\n                component: PluginsManagerContainer,\n            },")
if has_versions:
    imports.append("import VersionChangerContainer from '@/components/server/versionchanger/VersionChangerContainer';")
    tools_routes.append("            {\n                path: '/versions',\n                permission: 'file.*',\n                name: 'Versions',\n                icon: LayersIcon,\n                component: VersionChangerContainer,\n                exact: true,\n            },")
if has_props:
    imports.append("import ServerConfigEditorContainer from '@/components/server/servercfg/ServerConfigEditor';")
    tools_routes.append("            {\n                path: '/properties',\n                permission: 'file.*',\n                name: 'Properties',\n                icon: DocumentTextIcon,\n                component: ServerConfigEditorContainer,\n            },")
if has_players:
    imports.append("import PlayerManagerContainer from '@/components/server/players/PlayerManagerContainer';")
    tools_routes.append("            {\n                path: '/players',\n                permission: 'file.*',\n                name: 'Players',\n                icon: UserGroupIcon,\n                component: PlayerManagerContainer,\n                exact: true,\n            },")

imports_block = "\n".join(imports)
tools_block = "\n".join(tools_routes)

routes_content = f"""import React, {{ lazy }} from 'react';
import DashboardContainer from '@/components/server/dashboard/DashboardContainer';
import ServerConsole from '@/components/server/console/ServerConsoleContainer';
import FullConsoleContainer from '@/components/server/console/FullConsoleContainer';
import DatabasesContainer from '@/components/server/databases/DatabasesContainer';
import ScheduleContainer from '@/components/server/schedules/ScheduleContainer';
import UsersContainer from '@/components/server/users/UsersContainer';
import BackupContainer from '@/components/server/backups/BackupContainer';
import NetworkContainer from '@/components/server/network/NetworkContainer';
import StartupContainer from '@/components/server/startup/StartupContainer';
import FileManagerContainer from '@/components/server/files/FileManagerContainer';
import SettingsContainer from '@/components/server/settings/SettingsContainer';
import AccountOverviewContainer from '@/components/dashboard/AccountOverviewContainer';
import ActivityLogContainer from '@/components/dashboard/activity/ActivityLogContainer';
import ServerActivityLogContainer from '@/components/server/ServerActivityLogContainer';
import {{ UserIcon, EyeIcon, ViewGridIcon, TerminalIcon, FolderOpenIcon, DatabaseIcon, CalendarIcon, UserGroupIcon, ArchiveIcon, GlobeIcon, AdjustmentsIcon, CogIcon, PuzzleIcon, CubeIcon, DocumentTextIcon, CodeIcon, CollectionIcon, SwitchHorizontalIcon, CloudDownloadIcon, ChipIcon }} from '@heroicons/react/outline';

{imports_block}

const LayersIcon = (props: React.ComponentProps<'svg'>) => React.createElement(
    'svg',
    {{ xmlns: 'http://www.w3.org/2000/svg', fill: 'none', viewBox: '0 0 24 24', stroke: 'currentColor', strokeWidth: 1.8, ...props }},
    React.createElement('path', {{ strokeLinecap: 'round', strokeLinejoin: 'round', d: 'M12 3L2 8l10 5 10-5-10-5z' }}),
    React.createElement('path', {{ strokeLinecap: 'round', strokeLinejoin: 'round', d: 'M2 12l10 5 10-5' }}),
    React.createElement('path', {{ strokeLinecap: 'round', strokeLinejoin: 'round', d: 'M2 16l10 5 10-5' }})
);

const FileEditContainer = lazy(() => import('@/components/server/files/FileEditContainer'));
const ScheduleEditContainer = lazy(() => import('@/components/server/schedules/ScheduleEditContainer'));

interface RouteDefinition {{
    path: string;
    name: string | undefined;
    component: React.ComponentType;
    icon?: React.ComponentType;
    exact?: boolean;
}}

interface ServerRouteDefinition extends RouteDefinition {{
    permission: string | string[] | null;
    nestId?: number;
    eggId?: number;
    nestIds?: number[];
    eggIds?: number[];
}}

interface Routes {{
    account: RouteDefinition[];
    server: {{
        general: ServerRouteDefinition[];
        management: ServerRouteDefinition[];
        tools: ServerRouteDefinition[];
        configuration: ServerRouteDefinition[];
    }};
}}

export default {{
    account: [
        {{ path: '/', name: 'account', icon: UserIcon, component: AccountOverviewContainer, exact: true }},
        {{ path: '/activity', name: 'account-activity', icon: EyeIcon, component: ActivityLogContainer }},
    ],
    server: {{
        general: [
            {{ path: '/', permission: null, name: 'dashboard', icon: ViewGridIcon, component: DashboardContainer, exact: true }},
            {{ path: '/console', permission: null, name: 'console', icon: TerminalIcon, component: ServerConsole, exact: true }},
            {{ path: '/console/popup', permission: null, icon: TerminalIcon, name: undefined, component: FullConsoleContainer }},
            {{ path: '/settings', permission: ['settings.*', 'file.sftp'], name: 'settings', icon: CogIcon, component: SettingsContainer }},
            {{ path: '/activity', permission: 'activity.*', name: 'activity', icon: EyeIcon, component: ServerActivityLogContainer }},
        ],
        management: [
            {{ path: '/files', permission: 'file.*', name: 'files', icon: FolderOpenIcon, component: FileManagerContainer }},
            {{ path: '/files/:action(edit|new)', permission: 'file.*', name: undefined, component: FileEditContainer }},
            {{ path: '/databases', permission: 'database.*', name: 'databases', icon: DatabaseIcon, component: DatabasesContainer }},
            {{ path: '/backups', permission: 'backup.*', name: 'backups', icon: ArchiveIcon, component: BackupContainer }},
            {{ path: '/network', permission: 'allocation.*', name: 'network', icon: GlobeIcon, component: NetworkContainer }},
        ],
        tools: [
{tools_block}
        ],
        configuration: [
            {{ path: '/schedules', permission: 'schedule.*', name: 'schedules', icon: CalendarIcon, component: ScheduleContainer }},
            {{ path: '/schedules/:id', permission: 'schedule.*', name: undefined, component: ScheduleEditContainer }},
            {{ path: '/users', permission: 'user.*', name: 'users', icon: UserGroupIcon, component: UsersContainer }},
            {{ path: '/startup', permission: 'startup.*', name: 'startup', icon: AdjustmentsIcon, component: StartupContainer }},
        ],
    }},
}} as Routes;
"""
routes_file.write_text(routes_content)

if re_file.exists():
    el = re_file.read_text()
    if "routes.server.tools" not in el:
        subnav_target = """      <div className="dropdown">
        <span>{t('management')} <ChevronDownIcon className="w-3"/></span>
        <div className="dropdown-body">
          {routes.server.management
            .filter((route) => !!route.name)
            .map((route) =>
              renderNavItem(route)
            )}
        </div>
      </div>"""
        subnav_tools = subnav_target + """
      <div className="dropdown">
        <span>Tools <ChevronDownIcon className="w-3"/></span>
        <div className="dropdown-body">
          {routes.server.tools
            .filter((route) => !!route.name)
            .map((route) =>
              renderNavItem(route)
            )}
        </div>
      </div>"""
        el = el.replace(subnav_target, subnav_tools, 1)

        nav_target = """      <div>
        <span>{t('management')}</span>
        {routes.server.management
          .filter((route) => !!route.name)
          .map((route) =>
            renderNavItem(route)
          )}
      </div>"""
        nav_tools = nav_target + """
      <div>
        <span>Tools</span>
        {routes.server.tools
          .filter((route) => !!route.name)
          .map((route) =>
            renderNavItem(route)
          )}
      </div>"""
        el = el.replace(nav_target, nav_tools, 1)

        switch_target = """          {routes.server.management.map(({ path, permission, component: Component, nestIds, eggIds, nestId, eggId }) => {
            return (
              ((nestIds && nestIds.includes(serverNestId ?? 0)) ||
                (eggIds && eggIds.includes(serverEggId ?? 0)) ||
                (nestId && serverNestId === nestId) ||
                (eggId && serverEggId === eggId) ||
                (!eggIds && !nestIds && !nestId && !eggId)) && (
                <PermissionRoute key={path} permission={permission} path={to(path)} exact>
                  <Spinner.Suspense>
                    <Component />
                  </Spinner.Suspense>
                </PermissionRoute>
              )
            );
          })}"""
        switch_tools = switch_target + """
          {routes.server.tools.map(({ path, permission, component: Component, nestIds, eggIds, nestId, eggId }) => {
            return (
              ((nestIds && nestIds.includes(serverNestId ?? 0)) ||
                (eggIds && eggIds.includes(serverEggId ?? 0)) ||
                (nestId && serverNestId === nestId) ||
                (eggId && serverEggId === eggId) ||
                (!eggIds && !nestIds && !nestId && !eggId)) && (
                <PermissionRoute key={path} permission={permission} path={to(path)} exact>
                  <Spinner.Suspense>
                    <Component />
                  </Spinner.Suspense>
                </PermissionRoute>
              )
            );
          })}"""
        el = el.replace(switch_target, switch_tools, 1)
        re_file.write_text(el)
PY
  ok 'Arix Tools navigation injected'
}

build_panel() {
  say 'Clearing cache & compiling frontend assets...'
  (cd "$PANEL_DIR" && php artisan route:clear && php artisan optimize:clear) >> "$LOG_FILE" 2>&1 &
  spinner $! "Clearing Laravel Cache..."
  ok "Cache cleared"

  if [[ -f "$PANEL_DIR/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
    (cd "$PANEL_DIR" && yarn build:production) >> "$LOG_FILE" 2>&1 &
  elif [[ -f "$PANEL_DIR/package.json" ]] && command -v npm >/dev/null 2>&1; then
    (cd "$PANEL_DIR" && npm run build:production) >> "$LOG_FILE" 2>&1 &
  else
    warn "No frontend build manager found. Skipping asset compilation."
    return 0
  fi
  spinner $! "Building Production Assets (Webpack/Vite)..."
  ok "Frontend assets compiled successfully"

  chown -R www-data:www-data "$PANEL_DIR"/* 2>/dev/null || true
}

menu() {
  printf "\n${ORANGE}  ┌────────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${ORANGE}  │${RESET} ${BOLD_WHITE}                   SELECT INSTALLATION MODE                 ${RESET}${ORANGE}│${RESET}\n"
  printf "${ORANGE}  ├────────────────────────────────────────────────────────────┤${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}1)${RESET} ${WHITE}Full Setup / Install All 4 Addons & Build               ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}2)${RESET} ${WHITE}Properties Addon Only                                  ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}3)${RESET} ${WHITE}Plugins Addon Only                                     ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}4)${RESET} ${WHITE}Player Manager Addon Only                              ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}5)${RESET} ${WHITE}Version Changer Addon Only                             ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}6)${RESET} ${WHITE}Select Multiple Custom Addons                          ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}7)${RESET} ${WHITE}Sync Uploaded Files & Rebuild Only                     ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  │${RESET}   ${BOLD}0)${RESET} ${WHITE}Exit Manager                                           ${ORANGE}│${RESET}\n"
  printf "${ORANGE}  └────────────────────────────────────────────────────────────┘${RESET}\n\n"
  
  local choice
  printf "${GOLD}  ➜${RESET} ${WHITE}Enter your choice [0-7]: ${RESET}"
  read -r choice
  case "$choice" in
    1) SELECTED=(blue plugins player version) ;;
    2) SELECTED=(blue) ;;
    3) SELECTED=(plugins) ;;
    4) SELECTED=(player) ;;
    5) SELECTED=(version) ;;
    6)
      for entry in 'blue:Properties' 'plugins:Plugins' 'player:Players' 'version:Versions'; do
        key="${entry%%:*}"; label="${entry#*:}"
        if confirm "Process $label addon?"; then SELECTED+=("$key"); fi
      done
      ((${#SELECTED[@]} > 0)) || die 'No addons selected.'
      ;;
    7)
      for key in blue plugins player version; do
        if is_addon_files_present "$key"; then SELECTED+=("$key"); fi
      done
      ((${#SELECTED[@]} > 0)) || die "No uploaded addon files found in $PANEL_DIR!"
      ;;
    0) exit 0 ;;
    *) die 'Invalid selection.' ;;
  esac
}

main() {
  banner
  need_cmd tee; need_cmd find; need_cmd tar
  check_panel
  menu
  printf '\n'
  confirm "Proceed with selected operations?" || die 'Operation cancelled.'
  prepare_deps
  WORK_DIR="$(mktemp -d -t xorvila-addon.XXXXXX)"
  touch "$LOG_FILE"
  
  for addon in "${SELECTED[@]}"; do
    case "$addon" in
      blue) install_blue ;;
      plugins) install_plugins ;;
      player) install_player ;;
      version) install_version_changer ;;
    esac
  done
  
  configure_arix_tools_layout
  build_panel
  
  banner
  show_addon_status
  print_box "SUCCESS: XORVILA ADDON DEPLOYMENT COMPLETE!" "$GREEN"
  say "Logs stored securely at: ${WHITE}$LOG_FILE${RESET}"
}

main "$@"
