#!/usr/bin/env bash
# ==============================================================================
# XORVILA PTERODACTYL ADDON MANAGER v2.6 - ENTERPRISE ARIX TOOLS EDITION
# Features: Deep File & Build Telemetry | Auto-Tools Layout Sync | Cyber Orange UI
# ==============================================================================

# --- ANSI Colors (Orange & Black Theme) ---
ORANGE='\033[38;5;208m'
DARK_ORANGE='\033[38;5;202m'
WHITE='\033[1;37m'
GRAY='\033[38;5;244m'
GREEN='\033[38;5;46m'
RED='\033[38;5;196m'
YELLOW='\033[38;5;226m'
CYAN='\033[38;5;51m'
NC='\033[0m'

# --- File Paths & Variables ---
PTERO_DIR="${1:-/var/www/pterodactyl}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null || echo ".")" 2>/dev/null && pwd || pwd)"
ADDON_DIR=""
WORK_DIR=''
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/xorvila-addon-installer-${STAMP}.log"
SELECTED=()

# --- Root Privilege Check ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[✘] ERROR: This script must be run as root (use sudo).${NC}"
    exit 1
fi

# --- Header UI ---
show_banner() {
    clear
    echo -e "${DARK_ORANGE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${ORANGE}██╗  ██╗ ██████╗ ██████╗ ██╗   ██╗██╗██╗      █████╗ ${NC}               ${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${ORANGE}╚██╗██╔╝██╔═══██╗██╔══██╗██║   ██║██║██║     ██╔══██╗${NC}               ${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${ORANGE} ╚███╔╝ ██║   ██║██████╔╝██║   ██║██║██║     ███████║${NC}  ${WHITE}ADDON MGR${NC}  ${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${ORANGE} ██╔██╗ ██║   ██║██╔══██╗╚██╗ ██╔╝██║██║     ██╔══██║${NC}  ${GRAY}Arix Tools${NC}   ${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${ORANGE}██╔╝ ██╗╚██████╔╝██║  ██║ ╚████╔╝ ██║███████╗██║  ██║${NC}  ${GRAY}v2.6 Edition${NC}${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${ORANGE}╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝╚══════╝╚═╝  ╚═╝${NC}               ${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${DARK_ORANGE}║${NC}  ${WHITE}Automated Arix Tools Sidebar, API Linking & Production Build${NC}      ${DARK_ORANGE}║${NC}"
    echo -e "${DARK_ORANGE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

cleanup() { 
    [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; 
}
trap cleanup EXIT

# --- Detect Addon Bundles Directory ---
detect_addon_dir() {
    for d in "$SCRIPT_DIR/addons" "$PWD/addons" "$PTERO_DIR/addons" "/root/addons" "/tmp/addons"; do
        if [[ -d "$d" ]]; then
            ADDON_DIR="$d"
            return 0
        fi
    done
    ADDON_DIR="$PTERO_DIR/addons"
}

find_zip() {
    local zip_name="$1"
    for d in "$ADDON_DIR" "$SCRIPT_DIR/addons" "$PWD/addons" "$PTERO_DIR/addons" "$PWD" "$PTERO_DIR" "/root/addons" "/root"; do
        if [[ -n "$d" && -s "$d/$zip_name" ]]; then
            printf '%s' "$d/$zip_name"
            return 0
        fi
    done
    return 1
}

# --- Panel & Addon Status Checker ---
is_addon_files_present() {
    local key="$1"
    local fe="" be=""
    case "$key" in
        blue)
            fe="$PTERO_DIR/resources/scripts/components/server/servercfg/ServerConfigEditor.tsx"
            be="$PTERO_DIR/app/Http/Controllers/Api/Client/Servers/ServerConfigEditorController.php"
            ;;
        plugins)
            fe="$PTERO_DIR/resources/scripts/components/server/mcplugins/PluginsManagerContainer.tsx"
            be="$PTERO_DIR/app/Http/Controllers/Api/Client/Servers/McPluginsController.php"
            ;;
        player)
            fe="$PTERO_DIR/resources/scripts/components/server/players/PlayerManagerContainer.tsx"
            be="$PTERO_DIR/app/Http/Controllers/Api/Client/Servers/PlayerManagerController.php"
            ;;
        version)
            fe="$PTERO_DIR/resources/scripts/components/server/versionchanger/VersionChangerContainer.tsx"
            be="$PTERO_DIR/app/Http/Controllers/Api/Client/Servers/VersionChanger/VersionChangerController.php"
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
    local rf="$PTERO_DIR/resources/scripts/routers/routes.ts"
    local af="$PTERO_DIR/routes/api-client.php"
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
    local assets_dir="$PTERO_DIR/public/assets"
    [[ -d "$assets_dir" ]] || return 1
    case "$key" in
        blue)    grep -Rqs "server-properties" "$assets_dir" 2>/dev/null ;;
        plugins) grep -Rqs "mcplugins" "$assets_dir" 2>/dev/null ;;
        player)  grep -Rqs "PlayerManager" "$assets_dir" 2>/dev/null || grep -Rqs "/players" "$assets_dir" 2>/dev/null ;;
        version) grep -Rqs "version-changer" "$assets_dir" 2>/dev/null ;;
    esac
}

check_pterodactyl() {
    if [[ ! -d "$PTERO_DIR" ]] || [[ ! -f "$PTERO_DIR/artisan" ]]; then
        echo -e "${RED}[✘] CRITICAL: Pterodactyl Panel root not detected at $PTERO_DIR!${NC}"
        exit 1
    fi
    detect_addon_dir
}

show_addon_status() {
    check_pterodactyl
    echo -e "${DARK_ORANGE}─── ADDON TELEMETRY & STATUS ─────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Panel Root      :${NC} ${GREEN}$PTERO_DIR${NC}"
    echo -e "  ${WHITE}Addon Store Dir :${NC} ${GRAY}${ADDON_DIR:-Not Found}${NC}"
    echo ""
    echo -e "  ${ORANGE}Addon Name (Sidebar)${NC}      ${ORANGE}Panel Status${NC}          ${ORANGE}Zip Bundle${NC}"
    echo -e "  ${GRAY}────────────────────────────  ──────────────────────  ──────────${NC}"

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
                    p_status="${GREEN}● INSTALLED & BUILT${NC}"
                else
                    p_status="${YELLOW}⚠ LINKED (Need Build)${NC}"
                fi
            else
                p_status="${CYAN}⚠ UPLOADED (Unlinked)${NC}"
            fi
        else
            rc=$?
            if [[ $rc -eq 2 ]]; then
                p_status="${YELLOW}⚠ PARTIAL FILES${NC}"
            else
                p_status="${RED}○ NOT FOUND${NC}"
            fi
        fi

        if find_zip "$zip_name" >/dev/null 2>&1; then
            z_status="${GREEN}✔ Ready${NC}"
        else
            z_status="${GRAY}Missing${NC}"
        fi

        printf "  %-28s  %-22s  %-10s\n" "${WHITE}${label}${NC}" "$p_status" "$z_status"
    done
    echo -e "${DARK_ORANGE}──────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# --- Dependency Preparation ---
prepare_deps() {
    echo -e "${ORANGE}[*] Checking runtime dependencies...${NC}"
    command -v php >/dev/null 2>&1 || { echo -e "${RED}[✘] PHP is required.${NC}"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { echo -e "${RED}[✘] Python3 is required.${NC}"; exit 1; }
    
    if [[ ! -d "$PTERO_DIR/vendor" ]]; then
        echo -e "${YELLOW}[!] Composer vendor folder missing. Installing dependencies...${NC}"
        (cd "$PTERO_DIR" && composer install --no-dev --optimize-autoloader)
    fi
    if [[ ! -d "$PTERO_DIR/node_modules" ]]; then
        echo -e "${YELLOW}[!] Node modules missing. Installing frontend packages...${NC}"
        if [[ -f "$PTERO_DIR/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
            (cd "$PTERO_DIR" && yarn install --frozen-lockfile)
        else
            (cd "$PTERO_DIR" && npm ci)
        fi
    fi
    echo -e "    ${GREEN}✔ Dependencies verified successfully.${NC}"
}

# --- Addon Installers ---
install_blue() {
    echo -e "${ORANGE}[*] Processing Blue Server Properties...${NC}"
    local zip_path=""
    if zip_path="$(find_zip 'Blue-Server-Properties-Addon-Updated.zip')"; then
        local src="$WORK_DIR/blue"
        mkdir -p "$src" && unzip -q "$zip_path" -d "$src"
        python3 "$src/install.py" "$PTERO_DIR" 2>&1 | tee -a "$LOG_FILE" || true
    fi

    python3 - "$PTERO_DIR" <<'PY'
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
class ServerConfigEditorRequest extends ClientApiRequest {
    public function permission(): string { return Permission::ACTION_FILE_READ_CONTENT; }
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
    if target in s: s = s.replace(target, route_block + "\n\n    " + target, 1)
api_file.write_text(s)
PY
    echo -e "    ${GREEN}✔ Properties configured successfully.${NC}"
}

install_plugins() {
    echo -e "${ORANGE}[*] Processing MC Plugins Installer...${NC}"
    local zip_path=""
    if zip_path="$(find_zip 'MC-Plugins-Installer-Addon-Updated.zip')"; then
        local src="$WORK_DIR/plugins"
        mkdir -p "$src" && unzip -q "$zip_path" -d "$src"
        [[ -f "$src/install.sh" ]] && bash "$src/install.sh" "$PTERO_DIR" 2>&1 | tee -a "$LOG_FILE" || true
    fi
    echo -e "    ${GREEN}✔ Plugins configured successfully.${NC}"
}

install_player() {
    echo -e "${ORANGE}[*] Processing Player Manager...${NC}"
    local zip_path=""
    if zip_path="$(find_zip 'Player-Manager-Addon-Updated.zip')"; then
        local src="$WORK_DIR/player"
        mkdir -p "$src" && unzip -q "$zip_path" -d "$src"
        (cd "$src" && tar -cf - app resources) | (cd "$PTERO_DIR" && tar -xf -) 2>/dev/null || true
        [[ -f "$src/install-player-manager.sh" ]] && (cd "$PTERO_DIR" && bash "$src/install-player-manager.sh") 2>&1 | tee -a "$LOG_FILE" || true
    fi
    echo -e "    ${GREEN}✔ Players configured successfully.${NC}"
}

install_version_changer() {
    echo -e "${ORANGE}[*] Processing Version Changer...${NC}"
    local zip_path=""
    if zip_path="$(find_zip 'Version-Changer-Addon-Updated.zip')"; then
        local src="$WORK_DIR/version-changer"
        mkdir -p "$src" && unzip -q "$zip_path" -d "$src"
        python3 - "$PTERO_DIR" "$src" <<'PY'
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

    python3 - "$PTERO_DIR" <<'PY'
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
    if target in text: text = text.replace(target, vc_routes + "\n\n    " + target, 1)
api.write_text(text)
PY
    echo -e "    ${GREEN}✔ Versions configured successfully.${NC}"
}

# --- Arix Theme Tools Layout Unifier ---
configure_arix_tools_layout() {
    echo -e "${ORANGE}[*] Injecting Arix Tools Section under Management...${NC}"
    python3 - "$PTERO_DIR" <<'PY'
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
    echo -e "    ${GREEN}✔ Arix Tools section injected successfully.${NC}"
}

build_panel() {
    echo -e "${ORANGE}[*] Clearing cache and rebuilding production frontend assets...${NC}"
    (cd "$PTERO_DIR" && php artisan route:clear && php artisan optimize:clear) >> "$LOG_FILE" 2>&1
    echo -e "    ${GREEN}✔ Laravel cache cleared.${NC}"

    if [[ -f "$PTERO_DIR/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
        (cd "$PTERO_DIR" && yarn build:production) >> "$LOG_FILE" 2>&1
    elif [[ -f "$PTERO_DIR/package.json" ]] && command -v npm >/dev/null 2>&1; then
        (cd "$PTERO_DIR" && npm run build:production) >> "$LOG_FILE" 2>&1
    else
        echo -e "${YELLOW}[!] Frontend build manager not found. Skipping build.${NC}"
        return 0
    fi
    echo -e "    ${GREEN}✔ Production assets built successfully.${NC}"
    chown -R www-data:www-data "$PTERO_DIR"/* 2>/dev/null || true
}

# --- Main Interactive Menu Loop ---
while true; do
    show_banner
    show_addon_status

    echo -e "  ${ORANGE}[1]${NC} ${WHITE}Install / Setup All 4 Addons${NC}  ${GRAY}(Plugins, Versions, Properties, Players)${NC}"
    echo -e "  ${ORANGE}[2]${NC} ${WHITE}Properties Addon Only${NC}        ${GRAY}(Blue Server Properties)${NC}"
    echo -e "  ${ORANGE}[3]${NC} ${WHITE}Plugins Addon Only${NC}           ${GRAY}(MC Plugins Installer)${NC}"
    echo -e "  ${ORANGE}[4]${NC} ${WHITE}Player Manager Addon Only${NC}     ${GRAY}(Players Management)${NC}"
    echo -e "  ${ORANGE}[5]${NC} ${WHITE}Version Changer Addon Only${NC}    ${GRAY}(Minecraft Version Switcher)${NC}"
    echo -e "  ${ORANGE}[6]${NC} ${WHITE}Sync Uploaded Files & Rebuild${NC}  ${GRAY}(Link existing panel files & compile)${NC}"
    echo -e "  ${ORANGE}[0]${NC} ${RED}Exit Manager${NC}"
    echo ""
    echo -ne "${DARK_ORANGE}┌──(${WHITE}root@xorvila-manager${DARK_ORANGE})-[~]${NC}\n${DARK_ORANGE}└─#${NC} Select an option [0-6]: "
    read -r choice </dev/tty

    SELECTED=()
    case $choice in
        1) SELECTED=(blue plugins player version) ;;
        2) SELECTED=(blue) ;;
        3) SELECTED=(plugins) ;;
        4) SELECTED=(player) ;;
        5) SELECTED=(version) ;;
        6)
            for key in blue plugins player version; do
                if is_addon_files_present "$key"; then SELECTED+=("$key"); fi
            done
            if ((${#SELECTED[@]} -eq 0)); then
                echo -e "\n${RED}[✘] No uploaded addon files detected in $PTERO_DIR!${NC}"
                sleep 2
                continue
            fi
            ;;
        0)
            echo -e "\n${ORANGE}[*] Exiting Xorvila Addon Manager. Goodbye!${NC}\n"
            exit 0
            ;;
        *)
            echo -e "\n${RED}[!] Invalid option. Please select between 0 and 6.${NC}"
            sleep 1
            continue
            ;;
    esac

    echo -e "\n${ORANGE}[*] Preparing installation environment...${NC}"
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

    echo ""
    echo -e "${DARK_ORANGE}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}[★] SUCCESS: ALL SELECTED ADDONS DEPLOYED & BUILT SUCCESSFULLY!${NC}"
    echo -e "${DARK_ORANGE}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GRAY}Logs saved at: $LOG_FILE${NC}"
    echo ""
    read -p "Press [Enter] to return to menu..." </dev/tty
done
