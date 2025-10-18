#!/bin/bash

# Скрипт для запуска сканирования всех образов в конкретном проекте Harbor

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

# Проверяем аргументы
if [ $# -eq 0 ]; then
    echo "Использование: $0 <project_name> [--force]"
    echo ""
    echo "Примеры:"
    echo "  $0 library"
    echo "  $0 test_project"
    echo "  $0 library --force"
    echo ""
    echo "Доступные проекты:"
    curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name'
    exit 1
fi

PROJECT_NAME=$1
FORCE_SCAN=false

# Проверяем флаг --force
if [ "$2" = "--force" ]; then
    FORCE_SCAN=true
    echo "🔍 Принудительное сканирование всех образов в проекте: $PROJECT_NAME"
else
    echo "🔍 Запуск сканирования всех образов в проекте: $PROJECT_NAME"
fi

# Проверяем, существует ли проект
project_exists=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r --arg project "$PROJECT_NAME" '.[] | select(.name == $project) | .name')

if [ -z "$project_exists" ]; then
    echo "❌ Проект '$PROJECT_NAME' не найден!"
    echo ""
    echo "Доступные проекты:"
    curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name'
    exit 1
fi

# Функция для запуска сканирования образа
scan_artifact() {
    local project=$1
    local repo=$2
    local digest=$3
    
    echo "📦 Сканирование: $project/$repo@${digest:0:19}..."
    
    response=$(curl -s -X POST -u "$USERNAME:$PASSWORD" \
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
    
    local scan_info=$(curl -s -u "$USERNAME:$PASSWORD" \
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
                if [ "$FORCE_SCAN" = true ]; then
                    echo "🔄 $project/$repo@${digest:0:19}... - Принудительное пересканирование (было: $total уязвимостей)"
                    return 0  # Запустим сканирование
                else
                    echo "✅ $project/$repo@${digest:0:19}... - Уже отсканирован (Уязвимостей: $total, H:$high M:$medium L:$low)"
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

echo "🏗️  Проект: $PROJECT_NAME"

# Получаем репозитории проекта
repos=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$PROJECT_NAME/repositories" | jq -r '.[].name')

if [ -z "$repos" ]; then
    echo "❌ В проекте '$PROJECT_NAME' нет репозиториев!"
    exit 1
fi

total_scanned=0
already_scanned=0
errors=0

for repo in $repos; do
    repo_name=$(echo $repo | sed "s/$PROJECT_NAME\///")
    echo ""
    echo "  📦 Репозиторий: $repo_name"
    
    # Получаем артефакты репозитория
    artifacts=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$PROJECT_NAME/repositories/$repo_name/artifacts" | jq -r '.[].digest')
    
    if [ -z "$artifacts" ]; then
        echo "    ⚠️  В репозитории нет артефактов"
        continue
    fi
    
    for digest in $artifacts; do
        # Сначала проверяем статус
        if check_artifact_scan "$PROJECT_NAME" "$repo_name" "$digest"; then
            # Если нужно запустить сканирование
            if scan_artifact "$PROJECT_NAME" "$repo_name" "$digest"; then
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
echo "📊 Статистика сканирования проекта '$PROJECT_NAME':"
echo "  Новых сканирований запущено: $total_scanned"
echo "  Уже отсканировано/выполняется: $already_scanned"
echo "  Ошибок: $errors"
echo "  Всего артефактов: $((total_scanned + already_scanned + errors))"

if [ $total_scanned -gt 0 ]; then
    echo ""
    echo "💡 Для проверки статуса сканирования используйте:"
    echo "   ./check_scan_status.sh"
fi

echo "✅ Готово!"
