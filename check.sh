#!/bin/bash

# Универсальный скрипт для проверки статуса сканирования образов в Harbor
# Поддерживает проверку конкретных проектов и всех образов

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
    echo "Использование: $0 [ОПЦИИ] [ПРОЕКТ]"
    echo ""
    echo "ОПЦИИ:"
    echo "  --all, -a          Показать все образы (включая отсканированные)"
    echo "  --unscanned, -u    Показать только неотсканированные образы (по умолчанию)"
    echo "  --help, -h         Показать эту справку"
    echo ""
    echo "ПРОЕКТ:"
    echo "  Имя проекта для проверки (если не указан, проверяются все проекты)"
    echo ""
    echo "ПРИМЕРЫ:"
    echo "  $0 library                    # Показать неотсканированные образы в проекте library"
    echo "  $0 library --all              # Показать все образы в проекте library"
    echo "  $0 --unscanned                # Показать неотсканированные образы во всех проектах"
    echo "  $0 --all                      # Показать все образы во всех проектах"
    echo ""
    echo "Доступные проекты:"
    curl -s -H "Authorization: Basic $AUTH_TOKEN" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name' 2>/dev/null || echo "Не удалось получить список проектов"
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

# Функция для проверки статуса сканирования образа
check_artifact_scan() {
    local project=$1
    local repo=$2
    local digest=$3
    local show_all=$4
    
    local scan_info=$(curl -s -H "Authorization: Basic $AUTH_TOKEN" \
        "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo/artifacts/$digest?with_scan_overview=true" | \
        jq -r '.scan_overview."application/vnd.security.vulnerability.report; version=1.1"')
    
    if [ "$scan_info" != "null" ]; then
        local status=$(echo "$scan_info" | jq -r '.scan_status')
        local start_time=$(echo "$scan_info" | jq -r '.start_time')
        local end_time=$(echo "$scan_info" | jq -r '.end_time')
        
        case $status in
            "Success")
                local summary=$(echo "$scan_info" | jq -r '.summary')
                local total=$(echo "$summary" | jq -r '.total')
                local high=$(echo "$summary" | jq -r '.summary.High // 0')
                local medium=$(echo "$summary" | jq -r '.summary.Medium // 0')
                local low=$(echo "$summary" | jq -r '.summary.Low // 0')
                local critical=$(echo "$summary" | jq -r '.summary.Critical // 0')
                local unknown=$(echo "$summary" | jq -r '.summary.Unknown // 0')
                local fixable=$(echo "$summary" | jq -r '.fixable // 0')
                
                # Получаем информацию о сканере
                local scanner_name=$(echo "$scan_info" | jq -r '.scanner.name // "Unknown"')
                local scanner_vendor=$(echo "$scan_info" | jq -r '.scanner.vendor // "Unknown"')
                local scanner_version=$(echo "$scan_info" | jq -r '.scanner.version // "Unknown"')
                
                # Определяем уровень критичности
                local severity_level=""
                if [ "$critical" -gt 0 ]; then
                    severity_level="🔴 КРИТИЧЕСКИЙ"
                elif [ "$high" -gt 0 ]; then
                    severity_level="🟠 ВЫСОКИЙ"
                elif [ "$medium" -gt 0 ]; then
                    severity_level="🟡 СРЕДНИЙ"
                elif [ "$low" -gt 0 ]; then
                    severity_level="🟢 НИЗКИЙ"
                else
                    severity_level="✅ БЕЗОПАСНЫЙ"
                fi
                
                if [ "$show_all" = true ]; then
                    echo "✅ $project/$repo@${digest:0:19}... - $severity_level"
                    echo "    📊 Уязвимости: $total (C:$critical H:$high M:$medium L:$low U:$unknown)"
                    echo "    🔧 Исправимо: $fixable"
                fi
                
                # Добавляем к общей статистике
                total_vulnerabilities=$((total_vulnerabilities + total))
                total_critical=$((total_critical + critical))
                total_high=$((total_high + high))
                total_medium=$((total_medium + medium))
                total_low=$((total_low + low))
                total_unknown=$((total_unknown + unknown))
                total_fixable=$((total_fixable + fixable))
                
                # Сохраняем информацию о сканере проекта (только один раз)
                if [ -z "$project_scanner_name" ]; then
                    project_scanner_name="$scanner_name"
                    project_scanner_vendor="$scanner_vendor"
                    project_scanner_version="$scanner_version"
                fi
                
                # Добавляем сканер в список
                local scanner_info="$scanner_name $scanner_version ($scanner_vendor)"
                if [ -z "$scanner_list" ]; then
                    scanner_list="$scanner_info"
                else
                    scanner_list="$scanner_list|$scanner_info"
                fi
                
                return 0  # Отсканирован
                ;;
            "Running")
                echo "🔄 $project/$repo@${digest:0:19}... - Выполняется сканирование"
                return 1  # Не отсканирован
                ;;
            "Error")
                echo "❌ $project/$repo@${digest:0:19}... - Ошибка сканирования"
                return 1  # Не отсканирован
                ;;
            "Pending")
                echo "⏳ $project/$repo@${digest:0:19}... - Ожидает сканирования"
                return 1  # Не отсканирован
                ;;
            *)
                echo "❓ $project/$repo@${digest:0:19}... - Неизвестный статус: $status"
                return 1  # Не отсканирован
                ;;
        esac
    else
        echo "⚠️  $project/$repo@${digest:0:19}... - Нет данных о сканировании"
        return 1  # Не отсканирован
    fi
}

# Функция для проверки конкретного проекта
check_project() {
    local project_name=$1
    local show_all=$2
    
    echo "🔍 Проверка статуса сканирования образов в проекте: $project_name"
    
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
    
    # Инициализируем статистику
    total_artifacts=0
    scanned_count=0
    unscanned_count=0
    running_count=0
    error_count=0
    pending_count=0
    
    # Статистика уязвимостей
    total_vulnerabilities=0
    total_critical=0
    total_high=0
    total_medium=0
    total_low=0
    total_unknown=0
    total_fixable=0
    
    # Статистика сканеров
    scanner_list=""
    project_scanner_name=""
    project_scanner_vendor=""
    project_scanner_version=""
    
    echo ""
    if [ "$show_all" = true ]; then
        echo "📋 Статус всех образов:"
    else
        echo "⚠️  Неотсканированные образы:"
    fi
    echo ""
    
    for repo in $repos; do
        repo_name=$(echo $repo | sed "s/$project_name\///")
        
        # Получаем артефакты репозитория с пагинацией
        artifacts=$(get_all_paginated "$HARBOR_URL/api/v2.0/projects/$project_name/repositories/$repo_name/artifacts" | jq -r '.digest')
        
        if [ -z "$artifacts" ]; then
            continue
        fi
        
        for digest in $artifacts; do
            total_artifacts=$((total_artifacts + 1))
            
            if check_artifact_scan "$project_name" "$repo_name" "$digest" "$show_all"; then
                scanned_count=$((scanned_count + 1))
            else
                unscanned_count=$((unscanned_count + 1))
                
                # Дополнительная статистика для неотсканированных
                scan_info=$(curl -s -H "Authorization: Basic $AUTH_TOKEN" \
                    "$HARBOR_URL/api/v2.0/projects/$project_name/repositories/$repo_name/artifacts/$digest?with_scan_overview=true" | \
                    jq -r '.scan_overview."application/vnd.security.vulnerability.report; version=1.1"')
                
                if [ "$scan_info" != "null" ]; then
                    status=$(echo "$scan_info" | jq -r '.scan_status')
                    case $status in
                        "Running") running_count=$((running_count + 1)) ;;
                        "Error") error_count=$((error_count + 1)) ;;
                        "Pending") pending_count=$((pending_count + 1)) ;;
                    esac
                else
                    pending_count=$((pending_count + 1))
                fi
            fi
        done
    done
    
    echo ""
    echo "📊 Статистика проекта '$project_name':"
    echo "  Всего образов: $total_artifacts"
    echo "  Отсканировано: $scanned_count"
    echo "  Не отсканировано: $unscanned_count"
    if [ $unscanned_count -gt 0 ]; then
        echo "    - Выполняется: $running_count"
        echo "    - Ошибки: $error_count"
        echo "    - Ожидает: $pending_count"
    fi
    
    if [ $scanned_count -gt 0 ]; then
        echo ""
        echo "🔍 Сводка по уязвимостям:"
        echo "  📊 Всего уязвимостей: $total_vulnerabilities"
        echo "  🔴 Критические: $total_critical"
        echo "  🟠 Высокие: $total_high"
        echo "  🟡 Средние: $total_medium"
        echo "  🟢 Низкие: $total_low"
        echo "  ❓ Неизвестные: $total_unknown"
        echo "  🔧 Исправимые: $total_fixable"
        
        # Определяем общий уровень риска проекта
        if [ $total_critical -gt 0 ]; then
            echo "  ⚠️  Общий уровень риска: 🔴 КРИТИЧЕСКИЙ"
        elif [ $total_high -gt 0 ]; then
            echo "  ⚠️  Общий уровень риска: 🟠 ВЫСОКИЙ"
        elif [ $total_medium -gt 0 ]; then
            echo "  ⚠️  Общий уровень риска: 🟡 СРЕДНИЙ"
        elif [ $total_low -gt 0 ]; then
            echo "  ⚠️  Общий уровень риска: 🟢 НИЗКИЙ"
        else
            echo "  ✅ Общий уровень риска: БЕЗОПАСНЫЙ"
        fi
        
        # Показываем информацию о сканере проекта
        if [ -n "$project_scanner_name" ]; then
            echo ""
            echo "🔍 Сканер проекта: $project_scanner_name $project_scanner_version ($project_scanner_vendor)"
        fi
    fi
    
    if [ $unscanned_count -gt 0 ]; then
        echo ""
        echo "💡 Для запуска сканирования используйте:"
        echo "   ./scan.sh $project_name --force"
    fi
    
    if [ $scanned_count -eq $total_artifacts ] && [ $total_artifacts -gt 0 ]; then
        echo ""
        echo "🎉 Все образы в проекте отсканированы!"
    fi
}

# Функция для проверки всех проектов
check_all_projects() {
    local show_all=$1
    
    echo "🔍 Проверка статуса сканирования образов во всех проектах"
    
    # Получаем все проекты с пагинацией
    projects=$(get_all_paginated "$HARBOR_URL/api/v2.0/projects" | jq -r '.name')
    
    if [ -z "$projects" ]; then
        echo "❌ Проекты не найдены"
        return 1
    fi
    
    total_checked=0
    total_scanned=0
    total_unscanned=0
    total_running=0
    total_errors=0
    total_pending=0
    
    for project in $projects; do
        echo ""
        echo "=========================================="
        check_project "$project" "$show_all"
        project_count=$((project_count + 1))
    done
    
    echo ""
    echo "📊 Общая статистика:"
    echo "  Обработано проектов: $project_count"
    echo "  Всего проверено: $total_checked"
    echo "  Отсканировано: $total_scanned"
    echo "  Не отсканировано: $total_unscanned"
}

# Парсинг аргументов
SHOW_ALL=false
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all|-a)
            SHOW_ALL=true
            shift
            ;;
        --unscanned|-u)
            SHOW_ALL=false
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

# Запускаем соответствующую функцию
if [ -n "$PROJECT_NAME" ]; then
    check_project "$PROJECT_NAME" "$SHOW_ALL"
else
    check_all_projects "$SHOW_ALL"
fi

echo ""
echo "✅ Готово!"
