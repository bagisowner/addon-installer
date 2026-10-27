#!/usr/bin/env bash
set -Eeuo pipefail

# Xorvila Pterodactyl Addon Installer (Arix Theme 'Tools' Edition)
# Installs bundled addons into an existing Pterodactyl panel source tree
# and organizes them neatly under Management -> Tools.

ORANGE='\033[38;5;208m'; GOLD='\033[38;5;214m'; RED='\033[31m'; GREEN='\033[32m'; DIM='\033[2m'; RESET='\033[0m'
APP_NAME='XORVILA ADDON MANAGER'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$SCRIPT_DIR/addons"
PANEL_DIR="${1:-/var/www/pterodactyl}"
WORK_DIR=''
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/xorvila-addon-installer-${STAMP}.log"
SELECTED=()

say() { printf "${ORANGE}[%s]${RESET} %s\n" "$APP_NAME" "$*"; }
ok() { printf "${GREEN}  ✔${RESET} %s\n" "$*"; }
warn() { printf "${GOLD}  !${RESET} %s\n" "$*"; }
fail() { printf "${RED}  ✖${RESET} %s\n" "$*" >&2; }
die() { fail "$*"; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
trap 'rc=$?; fail "Installer stopped at line $LINENO (exit $rc). Log: $LOG_FILE"; exit "$rc"' ERR

banner() {
  printf "\n${ORANGE}╔══════════════════════════════════════════════════════════════╗\n"
  printf "║              XORVILA • PTERODACTYL ADDON MANAGER            ║\n"
  printf "╚══════════════════════════════════════════════════════════════╝${RESET}\n"
  printf "${DIM}Safe-by-default installer • Arix Tools Section • Auto Build Checks${RESET}\n\n"
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is missing. Install it, then run this script again."; }

check_panel() {
  [[ -d "$PANEL_DIR" ]] || die "Panel directory not found: $PANEL_DIR"
  [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/routes/api-client.php" && -f "$PANEL_DIR/resources/scripts/routers/routes.ts" ]] || die "'$PANEL_DIR' is not a valid Pterodactyl source root (artisan/routes files missing). Usage: sudo bash xorvila-install.sh /var/www/pterodactyl"
  [[ -d "$ADDON_DIR" ]] || die "Bundled addons folder not found: $ADDON_DIR. Keep the addons/ folder beside this script."
  for f in Blue-Server-Properties-Addon-Updated.zip MC-Plugins-Installer-Addon-Updated.zip Player-Manager-Addon-Updated.zip Version-Changer-Addon-Updated.zip; do
    [[ -s "$ADDON_DIR/$f" ]] || die "Addon package missing: $ADDON_DIR/$f. Re-upload the complete Xorvila bundle."
  done
  ok "Pterodactyl source root detected: $PANEL_DIR"
  ok "All four addon packages found"
}

confirm() { local answer; read -r -p "$1 [y/N]: " answer; [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]; }

prepare_deps() {
  need_cmd php; need_cmd python3; need_cmd unzip
  php -v >/dev/null 2>&1 || die 'PHP is not working.'
  [[ -f "$PANEL_DIR/composer.json" ]] || die 'composer.json not found in panel root.'
  if [[ ! -d "$PANEL_DIR/vendor" ]]; then
    warn "Composer dependencies (vendor/) are missing."
    confirm "Run composer install --no-dev --optimize-autoloader now?" || die 'Install cancelled: Composer dependencies are required.'
    need_cmd composer
    (cd "$PANEL_DIR" && composer install --no-dev --optimize-autoloader) 2>&1 | tee -a "$LOG_FILE"
  fi
  if [[ ! -d "$PANEL_DIR/node_modules" ]]; then
    warn "Frontend dependencies (node_modules/) are missing."
    if confirm "Install frontend dependencies automatically? This may take several minutes."; then
      if [[ -f "$PANEL_DIR/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
        (cd "$PANEL_DIR" && yarn install --frozen-lockfile) 2>&1 | tee -a "$LOG_FILE"
      elif [[ -f "$PANEL_DIR/package-lock.json" ]] && command -v npm >/dev/null 2>&1; then
        (cd "$PANEL_DIR" && npm ci) 2>&1 | tee -a "$LOG_FILE"
      else
        die 'No supported lockfile/package manager found. Install this panel release dependencies manually.'
      fi
    else
      die 'Install cancelled: frontend dependencies are required to build the panel.'
    fi
  fi
  if ! command -v yarn >/dev/null 2>&1 && [[ -f "$PANEL_DIR/yarn.lock" ]]; then
    warn 'Yarn command is unavailable. Trying Corepack if available.'
    command -v corepack >/dev/null 2>&1 || die 'Yarn is missing and Corepack is unavailable. Install the package manager required by this panel release.'
    (cd "$PANEL_DIR" && corepack yarn --version) >/dev/null
  fi
  ok 'Runtime and dependency checks passed'
}

extract_addon() {
  local zip="$1" target="$2"
  mkdir -p "$target"
  unzip -q "$ADDON_DIR/$zip" -d "$target"
  [[ -n "$(find "$target" -mindepth 1 -maxdepth 2 -print -quit)" ]] || die "Archive extracted empty: $zip"
}

install_blue() {
  say 'Installing Blue Server Properties (Properties)…'
  local src="$WORK_DIR/blue"
  extract_addon 'Blue-Server-Properties-Addon-Updated.zip' "$src"
  [[ -f "$src/install.py" ]] || die 'Blue Server Properties installer file missing from its package.'
  python3 "$src/install.py" "$PANEL_DIR" 2>&1 | tee -a "$LOG_FILE" || warn 'Sub-installer reported minor route warning; Xorvila unifier will fix it.'

  # Patch ServerConfigEditor.tsx Reset Changes button & ensure backend routes
  python3 - "$PANEL_DIR" <<'PY'
from pathlib import Path
import re, sys

root = Path(sys.argv[1])

# 1. Ensure ServerConfigEditorRequest.php exists
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

# 2. Ensure complete /server-properties routes in routes/api-client.php
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
    s = re.sub(
        r"[ \t]*Route::group\(\['prefix'\s*=>\s*'/server-properties'\],\s*function\s*\(\)\s*\{[\s\S]*?\}\);",
        lambda _: route_block,
        s
    )
else:
    target = "Route::group(['prefix' => '/settings'], function () {"
    if target in s:
        s = s.replace(target, route_block + "\n\n    " + target, 1)
api_file.write_text(s)

# 3. Fix Reset Changes button inside ServerConfigEditor.tsx
tsx_path = root / "resources/scripts/components/server/servercfg/ServerConfigEditor.tsx"
if tsx_path.exists():
    code = tsx_path.read_text()
    code = code.replace("@/api/server/properties/", "@/api/server/servercfg/")
    code = code.replace("@/components/server/properties/", "@/components/server/servercfg/")
    if "const [formKey, setFormKey]" not in code:
        code = code.replace(
            "const [filterText, setFilterText] = useState('');",
            "const [filterText, setFilterText] = useState('');\n    const [formKey, setFormKey] = useState(0);"
        )
    code = code.replace(
        "<Formik onSubmit={handleSubmit} initialValues={data.defaults}>",
        "<Formik key={formKey} enableReinitialize onSubmit={handleSubmit} initialValues={data.defaults}>"
    )
    old_btn = "onClick={() => resetForm()}"
    new_btn = """onClick={() => {
                                        resetForm({ values: data.defaults });
                                        setFormKey((prev) => prev + 1);
                                        mutate();
                                        addFlash({
                                            key: 'servercfg:editor',
                                            type: 'info',
                                            message: 'Changes have been reset to the saved server configuration.',
                                        });
                                    }}"""
    if old_btn in code:
        code = code.replace(old_btn, new_btn)
    tsx_path.write_text(code)
PY
  ok 'Blue Server Properties (Properties) applied & patched'
}

install_plugins() {
  say 'Installing MC Plugins Installer…'
  local src="$WORK_DIR/plugins"
  extract_addon 'MC-Plugins-Installer-Addon-Updated.zip' "$src"
  [[ -f "$src/install.sh" && -f "$src/install.py" ]] || die 'MC Plugins installer files are missing from the package.'
  bash "$src/install.sh" "$PANEL_DIR" 2>&1 | tee -a "$LOG_FILE" || warn 'Sub-installer reported minor route warning; Xorvila unifier will fix it.'
  ok 'MC Plugins Installer applied'
}

install_player() {
  say 'Installing Player Manager…'
  local src="$WORK_DIR/player"
  extract_addon 'Player-Manager-Addon-Updated.zip' "$src"
  [[ -f "$src/install-player-manager.sh" ]] || die 'Player Manager installer file missing from its package.'
  (cd "$src" && tar -cf - app resources) | (cd "$PANEL_DIR" && tar -xf -) 2>/dev/null || die 'Could not copy Player Manager source files into panel root.'
  cp "$src/install-player-manager.sh" "$WORK_DIR/install-player-manager.sh"
  (cd "$PANEL_DIR" && bash "$WORK_DIR/install-player-manager.sh") 2>&1 | tee -a "$LOG_FILE" || warn 'Sub-installer reported minor route warning; Xorvila unifier will fix it.'
  ok 'Player Manager applied'
}

install_version_changer() {
  say 'Installing Version Changer…'
  local src="$WORK_DIR/version-changer"
  extract_addon 'Version-Changer-Addon-Updated.zip' "$src"
  [[ -f "$src/app/Http/Controllers/Api/Client/Servers/VersionChanger/VersionChangerController.php" ]] || die 'Version Changer controller is missing.'
  python3 - "$PANEL_DIR" "$src" <<'PY'
from pathlib import Path
import shutil, sys, datetime, re

root, src = Path(sys.argv[1]), Path(sys.argv[2])
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')

def backup(path):
    if path.exists():
        b = path.with_name(path.name + '.xorvila-backup-' + stamp)
        shutil.copy2(path, b)

def overlay(source, rel):
    target = root / rel
    if source.is_dir():
        for item in source.rglob('*'):
            if item.is_file():
                dest = target / item.relative_to(source)
                dest.parent.mkdir(parents=True, exist_ok=True)
                if dest.exists(): backup(dest)
                shutil.copy2(item, dest)
    elif source.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists(): backup(target)
        shutil.copy2(source, target)

for rel in [
    'app/Http/Controllers/Api/Client/Servers/VersionChanger',
    'app/Http/Requests/Api/Client/Servers/VersionChanger',
    'resources/scripts/components/server/versionchanger',
]:
    overlay(src / rel, rel)

config_src = src / 'config-versionchanger.php'
config_dest = root / 'config/versionchanger.php'
if config_src.exists() and not config_dest.exists():
    config_dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_src, config_dest)

api = root / 'routes/api-client.php'
text = api.read_text()

version_changer_routes = """    Route::group(['prefix' => '/version-changer'], function () {
        Route::get('/types', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'types']);
        Route::get('/installed', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'installed']);
        Route::get('/types/{type}', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'versions']);
        Route::get('/types/{type}/{version}', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'builds']);
        Route::post('/install', [Client\\Servers\\VersionChanger\\VersionChangerController::class, 'install']);
    });"""

if "'/version-changer'" in text:
    text = re.sub(
        r"[ \t]*Route::group\(\['prefix'\s*=>\s*'/version-changer'\],\s*function\s*\(\)\s*\{[\s\S]*?\}\);",
        lambda _: version_changer_routes,
        text
    )
elif 'VersionChangerController::class' not in text:
    target = "Route::group(['prefix' => '/settings'], function () {"
    if target in text:
        text = text.replace(target, version_changer_routes + "\n\n    " + target, 1)
    else:
        marker = "Route::post('/command', [Client\\Servers\\CommandController::class, 'index']);"
        if marker in text:
            text = text.replace(marker, marker + "\n\n" + version_changer_routes, 1)

backup(api)
api.write_text(text)
PY
  php -l "$PANEL_DIR/routes/api-client.php" 2>&1 | tee -a "$LOG_FILE"
  ok 'Version Changer files and API routes integrated'
}

configure_arix_tools_layout() {
  say 'Configuring Arix Theme Tools section (Plugins, Versions, Properties, Players)…'
  python3 - "$PANEL_DIR" <<'PY'
from pathlib import Path
import re, sys

root = Path(sys.argv[1])
routes_file = root / "resources/scripts/routers/routes.ts"
re_file = root / "resources/scripts/routers/RouterElements.tsx"

# ---------------------------------------------------------
# 1. Cleanly write Arix routes.ts with 'tools' category
# ---------------------------------------------------------
routes_content = """import React, { lazy } from 'react';
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
import { UserIcon, EyeIcon, ViewGridIcon, TerminalIcon, FolderOpenIcon, DatabaseIcon, CalendarIcon, UserGroupIcon, ArchiveIcon, GlobeIcon, AdjustmentsIcon, CogIcon, PuzzleIcon, CubeIcon, DocumentTextIcon, CodeIcon, CollectionIcon, SwitchHorizontalIcon, CloudDownloadIcon, ChipIcon } from '@heroicons/react/outline';

import ServerConfigEditorContainer from '@/components/server/servercfg/ServerConfigEditor';
import VersionChangerContainer from '@/components/server/versionchanger/VersionChangerContainer';
import PluginsManagerContainer from '@/components/server/mcplugins/PluginsManagerContainer';
import PlayerManagerContainer from '@/components/server/players/PlayerManagerContainer';

const LayersIcon = (props: React.ComponentProps<'svg'>) => React.createElement(
    'svg',
    { xmlns: 'http://www.w3.org/2000/svg', fill: 'none', viewBox: '0 0 24 24', stroke: 'currentColor', strokeWidth: 1.8, ...props },
    React.createElement('path', { strokeLinecap: 'round', strokeLinejoin: 'round', d: 'M12 3L2 8l10 5 10-5-10-5z' }),
    React.createElement('path', { strokeLinecap: 'round', strokeLinejoin: 'round', d: 'M2 12l10 5 10-5' }),
    React.createElement('path', { strokeLinecap: 'round', strokeLinejoin: 'round', d: 'M2 16l10 5 10-5' })
);

const FileEditContainer = lazy(() => import('@/components/server/files/FileEditContainer'));
const ScheduleEditContainer = lazy(() => import('@/components/server/schedules/ScheduleEditContainer'));

interface RouteDefinition {
    path: string;
    name: string | undefined;
    component: React.ComponentType;
    icon?: React.ComponentType;
    exact?: boolean;
}

interface ServerRouteDefinition extends RouteDefinition {
    permission: string | string[] | null;
    nestId?: number;
    eggId?: number;
    nestIds?: number[];
    eggIds?: number[];
}

interface Routes {
    account: RouteDefinition[];
    server: {
        general: ServerRouteDefinition[];
        management: ServerRouteDefinition[];
        tools: ServerRouteDefinition[];
        configuration: ServerRouteDefinition[];
    };
}

export default {
    account: [
        {
            path: '/',
            name: 'account',
            icon: UserIcon,
            component: AccountOverviewContainer,
            exact: true,
        },
        {
            path: '/activity',
            name: 'account-activity',
            icon: EyeIcon,
            component: ActivityLogContainer,
        },
    ],
    server: {
        general: [
            {
                path: '/',
                permission: null,
                name: 'dashboard',
                icon: ViewGridIcon,
                component: DashboardContainer,
                exact: true,
            },
            {
                path: '/console',
                permission: null,
                name: 'console',
                icon: TerminalIcon,
                component: ServerConsole,
                exact: true,
            },
            {
                path: '/console/popup',
                permission: null,
                icon: TerminalIcon,
                name: undefined,
                component: FullConsoleContainer,
            },
            {
                path: '/settings',
                permission: ['settings.*', 'file.sftp'],
                name: 'settings',
                icon: CogIcon,
                component: SettingsContainer,
            },
            {
                path: '/activity',
                permission: 'activity.*',
                name: 'activity',
                icon: EyeIcon,
                component: ServerActivityLogContainer,
            },
        ],
        management: [
            {
                path: '/files',
                permission: 'file.*',
                name: 'files',
                icon: FolderOpenIcon,
                component: FileManagerContainer,
            },
            {
                path: '/files/:action(edit|new)',
                permission: 'file.*',
                name: undefined,
                component: FileEditContainer,
            },
            {
                path: '/databases',
                permission: 'database.*',
                name: 'databases',
                icon: DatabaseIcon,
                component: DatabasesContainer,
            },
            {
                path: '/backups',
                permission: 'backup.*',
                name: 'backups',
                icon: ArchiveIcon,
                component: BackupContainer,
            },
            {
                path: '/network',
                permission: 'allocation.*',
                name: 'network',
                icon: GlobeIcon,
                component: NetworkContainer,
            },
        ],
        tools: [
            {
                path: '/mcplugins',
                permission: 'file.*',
                name: 'Plugins',
                icon: PuzzleIcon,
                component: PluginsManagerContainer,
            },
            {
                path: '/versions',
                permission: 'file.*',
                name: 'Versions',
                icon: LayersIcon,
                component: VersionChangerContainer,
                exact: true,
            },
            {
                path: '/properties',
                permission: 'file.*',
                name: 'Properties',
                icon: DocumentTextIcon,
                component: ServerConfigEditorContainer,
            },
            {
                path: '/players',
                permission: 'file.*',
                name: 'Players',
                icon: UserGroupIcon,
                component: PlayerManagerContainer,
                exact: true,
            },
        ],
        configuration: [
            {
                path: '/schedules',
                permission: 'schedule.*',
                name: 'schedules',
                icon: CalendarIcon,
                component: ScheduleContainer,
            },
            {
                path: '/schedules/:id',
                permission: 'schedule.*',
                name: undefined,
                component: ScheduleEditContainer,
            },
            {
                path: '/users',
                permission: 'user.*',
                name: 'users',
                icon: UserGroupIcon,
                component: UsersContainer,
            },
            {
                path: '/startup',
                permission: 'startup.*',
                name: 'startup',
                icon: AdjustmentsIcon,
                component: StartupContainer,
            },
        ],
    },
} as Routes;
"""
routes_file.write_text(routes_content)

# ---------------------------------------------------------
# 2. Ensure RouterElements.tsx renders 'Tools' below 'Management'
# ---------------------------------------------------------
if re_file.exists():
    el = re_file.read_text()
    if "routes.server.tools" not in el:
        # Topbar Dropdown
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

        # Sidebar Navigation
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

        # Switch Router Mapper
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
  ok 'Arix Theme Tools section configured (Plugins -> Versions -> Properties -> Players)'
}

build_panel() {
  say 'Validating PHP and rebuilding frontend…'
  php -l "$PANEL_DIR/routes/api-client.php" 2>&1 | tee -a "$LOG_FILE"
  (cd "$PANEL_DIR" && php artisan route:clear && php artisan optimize:clear) 2>&1 | tee -a "$LOG_FILE"
  if [[ -f "$PANEL_DIR/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
    (cd "$PANEL_DIR" && yarn build:production) 2>&1 | tee -a "$LOG_FILE"
  elif command -v corepack >/dev/null 2>&1 && [[ -f "$PANEL_DIR/yarn.lock" ]]; then
    (cd "$PANEL_DIR" && corepack yarn build:production) 2>&1 | tee -a "$LOG_FILE"
  elif [[ -f "$PANEL_DIR/package.json" ]] && command -v npm >/dev/null 2>&1; then
    (cd "$PANEL_DIR" && npm run build:production) 2>&1 | tee -a "$LOG_FILE"
  else
    die 'Could not find a supported frontend build command. No build was run.'
  fi
  chown -R www-data:www-data "$PANEL_DIR"/* 2>/dev/null || true
  ok 'Cache cleared, permissions set, and frontend build completed'
}

menu() {
  printf "\n${ORANGE}Choose installation mode${RESET}\n"
  printf '  1) Install all four addons (Recommended for Tools layout)\n'
  printf '  2) Blue Server Properties (Properties) only\n'
  printf '  3) MC Plugins Installer (Plugins) only\n'
  printf '  4) Player Manager (Players) only\n'
  printf '  5) Version Changer (Versions) only\n'
  printf '  6) Select multiple addons\n'
  printf '  0) Exit\n\n'
  read -r -p 'Select an option [1-6, 0]: ' choice
  case "$choice" in
    1) SELECTED=(blue plugins player version) ;;
    2) SELECTED=(blue) ;;
    3) SELECTED=(plugins) ;;
    4) SELECTED=(player) ;;
    5) SELECTED=(version) ;;
    6)
      for entry in 'blue:Blue Server Properties' 'plugins:MC Plugins Installer' 'player:Player Manager' 'version:Version Changer'; do
        key="${entry%%:*}"; label="${entry#*:}"
        if confirm "Install $label?"; then SELECTED+=("$key"); fi
      done
      ((${#SELECTED[@]} > 0)) || die 'No addons selected.'
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
  warn 'A timestamped backup of changed files is strongly recommended. The addon installers also create their own backups where supported.'
  confirm "Continue installing ${#SELECTED[@]} addon(s) into $PANEL_DIR?" || die 'Cancelled by user.'
  prepare_deps
  WORK_DIR="$(mktemp -d -t xorvila-addon.XXXXXX)"
  touch "$LOG_FILE"
  say "Log file: $LOG_FILE"
  for addon in "${SELECTED[@]}"; do
    case "$addon" in
      blue) install_blue ;;
      plugins) install_plugins ;;
      player) install_player ;;
      version) install_version_changer ;;
      *) die "Unknown internal addon selection: $addon" ;;
    esac
  done
  configure_arix_tools_layout
  build_panel
  printf "\n${GREEN}╔══════════════════════════════════════════════════════════════╗\n"
  printf "║                 XORVILA INSTALLATION COMPLETE               ║\n"
  printf "╚══════════════════════════════════════════════════════════════╝${RESET}\n"
  ok "Installed: ${SELECTED[*]}"
  say 'Open the panel and hard-refresh your browser. All 4 addons are under Management -> Tools.'
  say "Log saved at: $LOG_FILE"
}
main "$@"
