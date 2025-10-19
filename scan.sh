#!/bin/bash

# Универсальный скрипт для сканирования образов в Harbor
# Поддерживает сканирование конкретных проектов и всех образов

# Загружаем конфигурацию
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/harbor.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Файл конфигурации не найден: $CONFIG_FILE"
    echo "Создайте файл harbor.conf с настройками подключения к Harbor"
    exit 1
fi

# Функция для отображения справки
show_help() {
    # Загружаем конфигурацию для отображения списка проектов
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CONFIG_FILE="$SCRIPT_DIR/harbor.conf"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    echo "Использование: $0 [ОПЦИИ] [ПРОЕКТ]"
    echo ""
    echo "ОПЦИИ:"
    echo "  --all, -a          Сканировать все образы во всех проектах"
    echo "  --force, -f        Принудительное сканирование (пересканировать уже отсканированные)"
    echo "  --help, -h         Показать эту справку"
    echo ""
    echo "ПРОЕКТ:"
    echo "  Имя проекта для сканирования (если не указан --all)"
    echo ""
    echo "ПРИМЕРЫ:"
    echo "  $0 library                    # Сканировать проект library"
    echo "  $0 library --force            # Принудительно сканировать проект library"
    echo "  $0 --all                      # Сканировать все проекты (с подтверждением)"
    echo "  $0 --all --force              # Принудительно сканировать все проекты"
    echo ""
    echo "Доступные проекты:"
    get_all_paginated "$HARBOR_URL/api/v2.0/projects" | jq -r '.name' 2>/dev/null || echo "Не удалось получить список проектов"
}

# Функция для получения всех данных с пагинацией
get_all_paginated() {
    local url=$1
    local page_size=${2:-100}
    local all_data=""
    local page=1
    
    while true; do
        local current_url="${url}?page=${page}&page_size=${page_size}"
        local response=$(curl -s -H "Authorization: Basic $AUTH_TOKEN" "$current_url")
        
        if [ $? -ne 0 ]; then
            echo "❌ Ошибка при получении данных с страницы $page" >&2
            return 1
        fi
        
        # Проверяем, есть ли данные на текущей странице
        local page_data=$(echo "$response" | jq -r '.[]' 2>/dev/null)
        if [ -z "$page_data" ] || [ "$page_data" = "null" ]; then
            break
        fi
        
        # Добавляем данные к общему результату
        if [ -z "$all_data" ]; then
            all_data="$page_data"
        else
            all_data="$all_data
$page_data"
        fi
        
        # Проверяем, есть ли следующая страница
        local next_link=$(curl -s -I -H "Authorization: Basic $AUTH_TOKEN" "$current_url" | grep -i "link:" | grep -o 'rel="next"' || true)
        if [ -z "$next_link" ]; then
            break
        fi
        
        page=$((page + 1))
    done
    
    echo "$all_data"
}

# Функция для запуска сканирования образа
scan_artifact() {
    local project=$1
    local repo=$2
    local digest=$3
    
    echo "📦 Сканирование: $project/$repo@${digest:0:19}..."
    
    response=$(curl -s -X POST -H "Authorization: Basic $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d '{}' \
        "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo/artifacts/$digest/scan")
    
    if [ $? -eq 0 ]; then
        echo "✅ Сканирование запущено для $project/$repo@${digest:0:19}..."
        return 0
    else
        echo "❌ Ошибка сканирования для $project/$repo@${digest:0:19}..."
        return 1
    fi
}

# Функция для проверки статуса сканирования образа
check_artifact_scan() {
    local project=$1
    local repo=$2
    local digest=$3
    
    local scan_info=$(curl -s -H "Authorization: Basic $AUTH_TOKEN" \
        "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo/artifacts/$digest?with_scan_overview=true" | \
        jq -r '.scan_overview."application/vnd.security.vulnerability.report; version=1.1"')
    
    if [ "$scan_info" != "null" ]; then
        local status=$(echo "$scan_info" | jq -r '.scan_status')
        case $status in
            "Success")
                local summary=$(echo "$scan_info" | jq -r '.summary')
                local total=$(echo "$summary" | jq -r '.total')
                local high=$(echo "$summary" | jq -r '.summary.High // 0')
                local medium=$(echo "$summary" | jq -r '.summary.Medium // 0')
                local low=$(echo "$summary" | jq -r '.summary.Low // 0')
                local critical=$(echo "$summary" | jq -r '.summary.Critical // 0')
                
                if [ "$FORCE_SCAN" = true ]; then
                    echo "🔄 $project/$repo@${digest:0:19}... - Принудительное пересканирование (было: $total уязвимостей)"
                    return 0  # Запустим сканирование
                else
                    echo "✅ $project/$repo@${digest:0:19}... - Уже отсканирован (Уязвимостей: $total, C:$critical H:$high M:$medium L:$low)"
                    return 1  # Уже отсканирован
                fi
                ;;
            "Running")
                if [ "$FORCE_SCAN" = true ]; then
                    echo "🔄 $project/$repo@${digest:0:19}... - Принудительное пересканирование (было выполняется)"
                    return 0  # Запустим сканирование
                else
                    echo "🔄 $project/$repo@${digest:0:19}... - Уже выполняется"
                    return 1  # Уже выполняется
                fi
                ;;
            "Error")
                echo "❌ $project/$repo@${digest:0:19}... - Ошибка сканирования, попробуем еще раз"
                return 0  # Попробуем еще раз
                ;;
            *)
                echo "ℹ️  $project/$repo@${digest:0:19}... - Статус: $status"
                return 0  # Попробуем запустить
                ;;
        esac
    else
        echo "⚠️  $project/$repo@${digest:0:19}... - Нет данных о сканировании"
        return 0  # Запустим сканирование
    fi
}

# Функция для сканирования конкретного проекта
scan_project() {
    local project_name=$1
    
    echo "🔍 Сканирование всех образов в проекте: $project_name"
    if [ "$FORCE_SCAN" = true ]; then
        echo "🔄 Режим: Принудительное сканирование"
    else
        echo "🔄 Режим: Обычное сканирование (пропуск уже отсканированных)"
    fi
    
    # Проверяем, существует ли проект
    project_exists=$(curl -s -H "Authorization: Basic $AUTH_TOKEN" "$HARBOR_URL/api/v2.0/projects" | jq -r --arg project "$project_name" '.[] | select(.name == $project) | .name')
    
    if [ -z "$project_exists" ]; then
        echo "❌ Проект '$project_name' не найден!"
        echo ""
        echo "Доступные проекты:"
        curl -s -H "Authorization: Basic $AUTH_TOKEN" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name'
        return 1
    fi
    
    echo "🏗️  Проект: $project_name"
    
    # Получаем репозитории проекта с пагинацией
    repos=$(get_all_paginated "$HARBOR_URL/api/v2.0/projects/$project_name/repositories" | jq -r '.name')
    
    if [ -z "$repos" ]; then
        echo "❌ В проекте '$project_name' нет репозиториев!"
        return 1
    fi
    
    total_scanned=0
    already_scanned=0
    errors=0
    
    for repo in $repos; do
        repo_name=$(echo $repo | sed "s/$project_name\///")
        echo ""
        echo "  📦 Репозиторий: $repo_name"
        
        # Получаем артефакты репозитория с пагинацией
        artifacts=$(get_all_paginated "$HARBOR_URL/api/v2.0/projects/$project_name/repositories/$repo_name/artifacts" | jq -r '.digest')
        
        if [ -z "$artifacts" ]; then
            echo "    ⚠️  В репозитории нет артефактов"
            continue
        fi
        
        for digest in $artifacts; do
            # Сначала проверяем статус
            if check_artifact_scan "$project_name" "$repo_name" "$digest"; then
                # Если нужно запустить сканирование
                if scan_artifact "$project_name" "$repo_name" "$digest"; then
                    total_scanned=$((total_scanned + 1))
                else
                    errors=$((errors + 1))
                fi
            else
                already_scanned=$((already_scanned + 1))
            fi
            
            sleep 1  # Небольшая пауза между запросами
        done
    done
    
    echo ""
    echo "📊 Статистика сканирования проекта '$project_name':"
    echo "  Новых сканирований запущено: $total_scanned"
    echo "  Уже отсканировано/выполняется: $already_scanned"
    echo "  Ошибок: $errors"
    echo "  Всего артефактов: $((total_scanned + already_scanned + errors))"
    
    if [ $total_scanned -gt 0 ]; then
        echo ""
        echo "💡 Для проверки статуса сканирования используйте:"
        echo "   ./check_unscanned_images.sh $project_name --all"
    fi
}

# Функция для сканирования всех проектов
scan_all_projects() {
    echo "🔍 Сканирование всех образов во всех проектах"
    if [ "$FORCE_SCAN" = true ]; then
        echo "🔄 Режим: Принудительное сканирование"
    else
        echo "🔄 Режим: Обычное сканирование (пропуск уже отсканированных)"
    fi
    echo "⚠️  ВНИМАНИЕ: Это может занять очень много времени!"
    echo ""
    echo "Вы уверены, что хотите продолжить? (yes/no)"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "❌ Операция отменена пользователем"
        exit 0
    fi
    
    echo "🚀 Начинаем сканирование..."
    
    # Получаем все проекты с пагинацией
    projects=$(get_all_paginated "$HARBOR_URL/api/v2.0/projects" | jq -r '.name')
    
    if [ -z "$projects" ]; then
        echo "❌ Проекты не найдены"
        return 1
    fi
    
    total_stats=0
    project_count=0
    
    for project in $projects; do
        echo ""
        echo "=========================================="
        scan_project "$project"
        project_count=$((project_count + 1))
    done
    
    echo ""
    echo "📊 Общая статистика:"
    echo "  Обработано проектов: $project_count"
    echo "  Всего сканирований: $total_stats"
}

# Парсинг аргументов
SCAN_ALL=false
FORCE_SCAN=false
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all|-a)
            SCAN_ALL=true
            shift
            ;;
        --force|-f)
            FORCE_SCAN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "❌ Неизвестная опция: $1"
            echo "Используйте $0 --help для справки"
            exit 1
            ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            else
                echo "❌ Слишком много аргументов"
                echo "Используйте $0 --help для справки"
                exit 1
            fi
            shift
            ;;
    esac
done

# Проверяем аргументы
if [ "$SCAN_ALL" = true ] && [ -n "$PROJECT_NAME" ]; then
    echo "❌ Ошибка: Нельзя указать и --all и имя проекта одновременно"
    echo "Используйте $0 --help для справки"
    exit 1
fi

if [ "$SCAN_ALL" = false ] && [ -z "$PROJECT_NAME" ]; then
    echo "❌ Ошибка: Укажите имя проекта или используйте --all"
    echo "Используйте $0 --help для справки"
    exit 1
fi

# Запускаем соответствующую функцию
if [ "$SCAN_ALL" = true ]; then
    scan_all_projects
else
    scan_project "$PROJECT_NAME"
fi

echo ""
echo "✅ Готово!"
